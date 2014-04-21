(function(angular) {
  'use strict';


  /**
   * Twitter widget controller
   */
  angular.module('calcentral.controllers').controller('twitterController', ['$scope', '$http', function($scope, $http) {
    // $http.get('/public/dummy/json/tweets.json').success(function(data) {
    //   $scope.tweets = data;
      // $scope.status = status;
      $scope.numberOfTweets = [1, 3, 5, 7, 10];
      $scope.tweets = [
        {
          "tweet": "This is the first tweet.",
          "user_name": "Barack Obama",
          "user_id": "BarackObama",
          "user_picture": "app/assets/images/glass_magnifying_200x175.jpg",
          "time": "3:15 PM - 17 Apr 2014",
          "retweets": "291",
          "favorites": "431",
          "id": 1
        },
        {
          "tweet": "This is the second tweet.",
          "user_name": "Cal Dining",
          "user_id": "CalDining",
          "user_picture": "app/assets/images/glass_magnifying_200x175.jpg",
          "time": "4:57 PM - 18 Apr 2014",
          "retweets": "10",
          "favorites": "4",
          "id": 2
        },
        {
          "tweet": "This is the third tweet.",
          "user_name": "UC Berkeley News",
          "user_id": "UCBerkeleyNews",
          "user_picture": "app/assets/images/glass_magnifying_200x175.jpg",
          "time": "10:40 AM - 19 Apr 2014",
          "retweets": "29",
          "favorites": "0",
          "id": 3
        },
        {
          "tweet": "This is the fourth tweet.",
          "user_name": "Cal",
          "user_id": "Cal",
          "user_picture": "app/assets/images/glass_magnifying_200x175.jpg",
          "time": "11:03 AM - 19 Apr 2014",
          "retweets": "291",
          "favorites": "431",
          "id": 4
        },
        {
          "tweet": "This is the fifth tweet.",
          "user_name": "Berkeley Engineering",
          "user_id": "Cal_Engineer",
          "user_picture": "app/assets/images/glass_magnifying_200x175.jpg",
          "time": "11:30 AM - 19 Apr 2014",
          "retweets": "1",
          "favorites": "1",
          "id": 5
        },
        {
          "tweet": "This is the sixth tweet.",
          "user_name": "Berkeley News",
          "user_id": "berkeleymedia",
          "user_picture": "app/assets/images/glass_magnifying_200x175.jpg",
          "time": "1:04 PM - 19 Apr 2014",
          "retweets": "11",
          "favorites": "4",
          "id": 6
        },
        {
          "tweet": "This is the seventh tweet.",
          "user_name": "berkeley art center",
          "user_id": "BerkeleyArt",
          "user_picture": "app/assets/images/glass_magnifying_200x175.jpg",
          "time": "1:09 PM - 19 Apr 2014",
          "retweets": "3",
          "favorites": "3",
          "id": 7
        },
        {
          "tweet": "This is the eighth tweet.",
          "user_name": "UC Berkeley Law",
          "user_id": "BerkeleyLawNews",
          "user_picture": "app/assets/images/glass_magnifying_200x175.jpg",
          "time": "2:58 PM - 19 Apr 2014",
          "retweets": "11",
          "favorites": "4",
          "id": 8
        },
        {
          "tweet": "This is the ninth tweet.",
          "user_name": "Berkeley Lab CS",
          "user_id": "LBNLcs",
          "user_picture": "app/assets/images/glass_magnifying_200x175.jpg",
          "time": "5:34 PM - 19 Apr 2014",
          "retweets": "0",
          "favorites": "8",
          "id": 9
        },
        {
          "tweet": "This is the tenth tweet.",
          "user_name": "Berkeley News",
          "user_id": "berkeleymedia",
          "user_picture": "app/assets/images/glass_magnifying_200x175.jpg",
          "time": "6:09 PM - 19 Apr 2014",
          "retweets": "6",
          "favorites": "10",
          "id": 10
        },
      ];

      //};

    // $http.get('/public/dummy/json/tweets.json').error(function(data) {
    //   $scope.tweets = data || "Request failed";
    //   //$scope.status = status;
    // });

      //$scope.orderProp = 'id';
    }
  //};
  ]);

})(window.angular);
