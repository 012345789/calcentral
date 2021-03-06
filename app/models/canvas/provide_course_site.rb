module Canvas
  class ProvideCourseSite < Csv
    include TorqueBox::Messaging::Backgroundable
    include ClassLogger

    attr_reader :uid, :status, :cache_key

    #####################################
    # Class Methods

    def self.unique_job_id
      Time.now.to_f.to_s.gsub('.', '')
    end

    def self.find(cache_key)
      Rails.cache.fetch(cache_key)
    end

    #####################################
    # Instance Methods

    # Currently this depends on an instructor's point of view.
    def initialize(uid, options = {})
      super()
      raise ArgumentError, "uid must be a String" if uid.class != String
      @uid = uid
      @status = 'New' # Changes to 'Processing', 'Completed', or 'Error'
      @errors = []
      @completed_steps = []
      @import_data = {}
      @cache_key = "canvas.courseprovision.#{@uid}.#{Canvas::ProvideCourseSite.unique_job_id}"
    end

    def create_course_site(term_slug, ccns, is_admin_by_ccns = false)
      @status = "Processing"
      save
      logger.info("Course provisioning job started. Job state updated in cache key #{@cache_key}")
      @import_data['term_slug'] = term_slug
      @import_data['term'] = find_term(term_slug)
      @import_data['ccns'] = ccns
      @import_data['is_admin_by_ccns'] = is_admin_by_ccns

      prepare_users_courses_list
      identify_department_subaccount
      prepare_course_site_definition
      prepare_section_definitions
      prepare_user_definitions unless is_admin_by_ccns
      prepare_course_site_memberships unless is_admin_by_ccns

      # TODO Upload ZIP archives instead and do more detailed parsing of the import status.
      import_course_site(@import_data['course_site_definition'])
      import_sections(@import_data['section_definitions'])
      import_users(@import_data['user_definitions']) unless is_admin_by_ccns
      import_enrollments(@import_data['course_memberships']) unless is_admin_by_ccns

      # TODO Perform initial import of official campus instructors for these sections.
      # TODO Perform initial import of official campus student enrollments.
      retrieve_course_site_details
      expire_instructor_sites_cache

      # TODO Expire user's Canvas-related caches to maintain UX consistency.
      @status = "Completed"
      save
    rescue StandardError => error
      logger.error("ERROR: #{error.message}; Completed steps: #{@completed_steps.inspect}; Import Data: #{@import_data.inspect}; UID: #{@uid}")
      @status = 'Error'
      @errors << error.message
      save
      raise error
    end

    def prepare_users_courses_list
      raise RuntimeError, "Unable to prepare course list. Term slug not present." if @import_data['term_slug'].blank?
      raise RuntimeError, "Unable to prepare course list. CCNs not present." if @import_data['ccns'].blank?

      if @import_data['is_admin_by_ccns']
        # Admins can specify semester and CCNs directly, without access checks.
        semester_wrapped_list = courses_list_from_ccns(@import_data['term_slug'], @import_data['ccns'])
        courses_list = semester_wrapped_list.present? ?
          semester_wrapped_list[0][:classes] :
          []
      else
        # Otherwise, the user must have instructor access (direct or inherited via section-nesting) to all sections.
        courses_list = filter_courses_by_ccns(candidate_courses_list, @import_data['term_slug'], @import_data['ccns'])
      end
      @import_data['courses'] = courses_list
      complete_step("Prepared courses list")
    end

    def identify_department_subaccount
      raise RuntimeError, "Unable identify department subaccount. Course list not loaded or empty." if @import_data['courses'].blank?

      # Derive course site SIS ID, course code (short name), and title from first section's course info.
      department = @import_data['courses'][0][:dept]

      # Check that we have a departmental location for this course.
      @import_data['subaccount'] = subaccount_for_department(department)

      complete_step("Identified department sub-account")
    end

    def prepare_course_site_definition
      raise RuntimeError, "Unable to prepare course site definition. Term data is not present." if @import_data['term'].blank?
      raise RuntimeError, "Unable to prepare course site definition. Department subaccount ID not present." if @import_data['subaccount'].blank?
      raise RuntimeError, "Unable to prepare course site definition. Courses list is not present." if @import_data['courses'].blank?

      # Because the course's term is not included in the "Create a new course" API, we must use CSV import.
      @import_data['course_site_definition'] = generate_course_site_definition(@import_data['term'][:yr], @import_data['term'][:cd], @import_data['subaccount'], @import_data['courses'][0])
      @import_data['sis_course_id'] = @import_data['course_site_definition']['course_id']
      @import_data['course_site_short_name'] = @import_data['course_site_definition']['short_name']
      complete_step("Prepared course site definition")
    end

    def prepare_section_definitions
      raise RuntimeError, "Unable to prepare section definitions. Term data is not present." if @import_data['term'].blank?
      raise RuntimeError, "Unable to prepare section definitions. SIS Course ID is not present." if @import_data['sis_course_id'].blank?
      raise RuntimeError, "Unable to prepare section definitions. Courses list is not present." if @import_data['courses'].blank?

      # Add Canvas course sections to match the source sections.
      # We could use the "Create course section" API, but to reduce API usage we instead use CSV import.
      @import_data['section_definitions'] = generate_section_definitions(@import_data['term'][:yr], @import_data['term'][:cd], @import_data['sis_course_id'], @import_data['courses'])
      complete_step("Prepared section definitions")
    end

    def prepare_user_definitions
      raise RuntimeError, "Unable to prepare user definition. User ID is not present." if @uid.blank?
      # Add current instructor so that link to course site will work.
      # TODO Can eliminate this step if we import all official instructors for the sections.
      @import_data['user_definitions'] = accumulate_user_data([@uid], [])
      complete_step("Prepared user definitions")
    end

    def prepare_course_site_memberships
      raise RuntimeError, "Unable to prepare course site memberships. Section definitions are not present." if @import_data['section_definitions'].blank?
      raise RuntimeError, "Unable to prepare course site memberships. User definitions are not present." if @import_data['user_definitions'].blank?
      @import_data['course_memberships'] = generate_course_memberships(@import_data['section_definitions'], @import_data['user_definitions'][0])
      complete_step("Prepared course site memberships")
    end

    def import_course_site(canvas_course_row)
      @import_data['courses_csv_file'] = make_courses_csv("#{csv_filename_prefix}-course.csv", [canvas_course_row])
      response = Canvas::SisImport.new.import_courses(@import_data['courses_csv_file'])
      raise RuntimeError, 'Course site could not be created.' if response.blank?
      logger.warn("Successfully imported course from: #{@import_data['courses_csv_file']}")
      complete_step("Imported course")
    end

    def import_sections(canvas_section_rows)
      @import_data['sections_csv_file'] = make_sections_csv("#{csv_filename_prefix}-sections.csv", canvas_section_rows)
      response = Canvas::SisImport.new.import_sections(@import_data['sections_csv_file'])
      if response.blank?
        logger.error("Imported course from #{@import_data['courses_csv_file']} but sections did not import from #{@import_data['sections_csv_file']}")
        raise RuntimeError, "Course site was created without any sections or members! Section import failed."
      else
        logger.warn("Successfully imported sections from: #{@import_data['sections_csv_file']}")
        complete_step("Imported sections")
      end
    end

    def import_users(canvas_user_rows)
      @import_data['users_csv_file'] = make_users_csv("#{csv_filename_prefix}-users.csv", canvas_user_rows)
      response = Canvas::SisImport.new.import_users(@import_data['users_csv_file'])
      if response.blank?
        logger.error("Imported course and sections from #{@import_data['courses_csv_file']}, #{@import_data['sections_csv_file']} but users did not import from #{@import_data['users_csv_file']}")
        raise RuntimeError, "Course site was created but members may be missing! User import failed."
      else
        logger.warn("Successfully imported users from: #{@import_data['users_csv_file']}")
        complete_step("Imported users")
      end
    end

    def import_enrollments(canvas_enrollment_rows)
      @import_data['enrollments_csv_file'] = make_enrollments_csv("#{csv_filename_prefix}-enrollments.csv", canvas_enrollment_rows)
      response = Canvas::SisImport.new.import_enrollments(@import_data['enrollments_csv_file'])
      if response.blank?
        logger.error("Imported course, sections, and users from #{@import_data['courses_csv_file']}, #{@import_data['sections_csv_file']}, #{@import_data['users_csv_file']} but memberships did not import from #{@import_data['enrollments_csv_file']}")
        raise RuntimeError, "Course site was created but members may not be enrolled! Enrollment import failed."
      else
        logger.warn("Successfully imported enrollments from: #{@import_data['enrollments_csv_file']}")
        complete_step("Imported instructor enrollment")
      end
    end

    def retrieve_course_site_details
      raise RuntimeError, "Unable to retrieve course site details. SIS Course ID not present." if @import_data['sis_course_id'].blank?
      @import_data['course_site_url'] = course_site_url(@import_data['sis_course_id'])
      complete_step("Retrieved new course site details")
    end

    def expire_instructor_sites_cache
      Canvas::UserCourses.expire(@uid)
      Canvas::MergedUserSites.expire(@uid)
      MyClasses::Merged.new(@uid).expire_cache
      MyAcademics::Merged.new(@uid).expire_cache
      complete_step("Clearing bCourses course site cache")
    end

    def csv_filename_prefix
      @export_filename_prefix ||= "#{@export_dir}/course_provision-#{DateTime.now.strftime('%F')}-#{SecureRandom.hex(8)}"
    end

    def course_site_url(sis_id)
      response = Canvas::Course.new(course_id: sis_id).course
      raise RuntimeError, "Unexpected error obtaining course site URL for #{sis_id}!" if response.blank?
      course_data = JSON.parse(response.body)
      "#{Settings.canvas_proxy.url_root}/courses/#{course_data['id']}"
    end

    def current_terms
      @current_terms ||= Settings.canvas_proxy.current_terms_codes.collect do |term|
        {
          yr: term.term_yr,
          cd: term.term_cd,
          slug: Berkeley::TermCodes.to_slug(term.term_yr, term.term_cd),
          name: Berkeley::TermCodes.to_english(term.term_yr, term.term_cd)
        }
      end
    end

    def find_term(term_slug)
      term_index = current_terms.index { |term| term[:slug] == term_slug }
      raise ArgumentError, "term_slug does not match current term code" if term_index.nil?
      current_terms[term_index]
    end

    def candidate_courses_list
      raise RuntimeError, "User ID not found for candidate" if @uid.blank?
      terms_filter = current_terms

      # Get all sections for which this user is an instructor, sorted in a useful fashion.
      # Since this happens to match what's shown by MyAcademics::Teaching for a given semester,
      # we can simply re-use the academics feed (so long as course site provisioning is restricted to
      # semesters supported by My Academics). Ideally, MyAcademics::Teaching would be efficiently cached
      # by user_id + term_yr + term_cd. But since we currently only cache at the level of the full
      # merged model, we're probably better off selecting the desired teaching-semester from that bigger feed.

      academics_feed = MyAcademics::Merged.new(@uid).get_feed
      if (teaching_semesters = academics_feed[:teaching_semesters])
        teaching_semesters.select do |teaching_semester|
          terms_filter.index { |term| teaching_semester[:slug] == term[:slug] }
        end
      else
        []
      end
    end

    # When an admin specifies CCNs directly, we cannot repurpose an existing MyAcademics::Teaching feed.
    # Instead, mimic its data structure.
    def courses_list_from_ccns(term_slug, ccns)
      courses_list = []
      term = find_term(term_slug)
      proxy = CampusOracle::UserCourses.new({user_id: @uid})
      feed = proxy.get_selected_sections(term[:yr], term[:cd], ccns)
      feed.keys.each do |term_key|
        (term_yr, term_cd) = term_key.split("-")
        semester = MyAcademics::AcademicsModule.semester_info(term_yr, term_cd)
        feed[term_key].each do |course|
          semester[:classes] << MyAcademics::AcademicsModule.class_info(course)
        end
        courses_list << semester unless semester[:classes].empty?
      end
      courses_list
    end

    def filter_courses_by_ccns(courses_list, term_slug, ccns)
      filtered = []
      idx = courses_list.index { |term| term[:slug] == term_slug }
      if idx.blank?
        logger.error("Specified term_slug '#{term_slug}' does not match current term code")
        raise ArgumentError, "No courses found!"
      end
      courses = courses_list[idx][:classes]
      courses.each do |course|
        filtered_sections = []
        course[:sections].each do |section|
          if ccns.include?(section[:ccn])
            filtered_sections << section
            ccns.delete(section[:ccn])
          end
        end
        if !filtered_sections.empty?
          course[:sections] = filtered_sections
          filtered << course
        end
      end
      logger.warn("User #{@uid} tried to provision inaccessible CCNs: #{ccns.inspect}") if ccns.any?
      filtered
    end

    # We add the instructor as a teacher in the default section of the course. This should
    # be enough to grant site access before a full campus data refresh is done.
    def generate_course_memberships(section_rows, instructor_row)
      enrollments = []
      section_rows.each do |section_row|
        enrollments << {
          'course_id' => section_row['course_id'],
          'user_id' => instructor_row['user_id'],
          'role' => 'teacher',
          'section_id' => section_row['section_id'],
          'status' => 'active'
        }
      end
      enrollments
    end

    def generate_course_site_definition(term_yr, term_cd, subaccount, campus_course_data)
      if (sis_id = generate_unique_sis_course_id(Canvas::ExistenceCheck.new, campus_course_data[:slug], term_yr, term_cd))
        {
          'course_id' => sis_id,
          'short_name' => campus_course_data[:course_code],
          'long_name' => campus_course_data[:title] || campus_course_data[:course_code],
          'account_id' => subaccount,
          'term_id' => Canvas::Proxy.term_to_sis_id(term_yr, term_cd),
          'status' => 'active'
        }
      else
        logger.error("Unable to generate unique Canvas course SIS ID for '#{campus_course_data[:course_code]}'; will NOT create site")
        raise RuntimeError, "Could not define new course site!"
      end
    end

    def generate_section_definitions(term_yr, term_cd, sis_course_id, campus_section_data)
      raise ArgumentError, "'campus_section_data' argument is empty" if campus_section_data.empty?
      sections = []
      existence_proxy = Canvas::ExistenceCheck.new
      campus_section_data.each do |course|
        course[:sections].each do |section|
          if (sis_section_id = generate_unique_sis_section_id(existence_proxy, section[:ccn], term_yr, term_cd))
            sections << {
              'section_id' => sis_section_id,
              'course_id' => sis_course_id,
              'name' => "#{course[:course_code]} #{section[:section_label]}",
              'status' => 'active'
            }
          else
            logger.error("Unable to generate unique Canvas section SIS ID for CCN #{section[:ccn]} in #{source}; will NOT create section")
          end
        end
      end
      sections
    end

    def generate_unique_sis_course_id(existence_proxy, slug, term_yr, term_cd)
      sis_id_root = "#{slug}-#{term_yr}-#{term_cd}"
      sis_id_suffix = ''
      sis_id = nil
      retriable(on: Canvas::ProvideCourseSite::IdNotUniqueException, tries: 20) do
        candidate = "CRS:#{sis_id_root}#{sis_id_suffix}".upcase
        if existence_proxy.course_defined?(candidate)
          logger.info("Already have Canvas course with SIS ID #{candidate}")
          sis_id_suffix = "-#{SecureRandom.hex(4)}"
          raise Canvas::ProvideCourseSite::IdNotUniqueException
        else
          sis_id = candidate
        end
      end
      sis_id
    end

    def generate_unique_sis_section_id(existence_proxy, ccn, term_yr, term_cd)
      sis_id_root = "#{term_yr}-#{term_cd}-#{ccn}"
      sis_id_suffix = ''
      sis_id = nil
      retriable(on: Canvas::ProvideCourseSite::IdNotUniqueException, tries: 20) do
        candidate = "SEC:#{sis_id_root}#{sis_id_suffix}".upcase
        if existence_proxy.section_defined?(candidate)
          logger.info("Already have Canvas section with SIS ID #{candidate}")
          sis_id_suffix = "-#{SecureRandom.hex(4)}"
          raise Canvas::ProvideCourseSite::IdNotUniqueException
        else
          sis_id = candidate
        end
      end
      sis_id
    end

    def subaccount_for_department(department)
      subaccount = "ACCT:#{department}"
      if !Canvas::ExistenceCheck.new.account_defined?(subaccount)
        # There is no programmatic way to create a subaccount in Canvas.
        logger.error("Cannot provision course site; bCourses account #{subaccount} does not exist!")
        raise RuntimeError, "Could not find bCourses account for department #{department}"
      else
        subaccount
      end
    end

    def save
      raise RuntimeError, "Unable to save. cache_key missing" if @cache_key.blank?
      raise RuntimeError, "Unable to save. Cache expiration setting not present." if Settings.cache.expiration.CanvasCourseProvisioningJobs == nil
      Rails.cache.write(@cache_key, self, expires_in: Settings.cache.expiration.CanvasCourseProvisioningJobs)
    end

    def complete_step(step_text)
      @completed_steps << step_text
      save
    end

    def to_json
      job_status = {
        job_id: @cache_key,
        status: @status,
        completed_steps: @completed_steps,
        percent_complete: (@completed_steps.count.to_f / 12.0).round(2),
      }
      job_status['error'] = @errors.join('; ') if @errors.count > 0
      job_status['course_site'] = {short_name: @import_data['course_site_short_name'], url: @import_data['course_site_url']} if @status == 'Completed'
      job_status.to_json
    end

    def job_id
      @cache_key
    end

    class IdNotUniqueException < Exception
    end

  end
end
