(function(angular) {
  'use strict';

  /**
   * Meal Points controller
   */
  angular.module('calcentral.controllers').controller('cal1cardController', function($scope) {

    $scope.amount = 0;

    $scope.addAmount = function() {
    	$scope.amount += 10;
    }

    $scope.donateAmount = function() {
    	$scope.amount -= 10;
    }

    $scope.buttons = [
    	{'cal1cardButtonLabel': '+ Add Meal Points', 
    	'cal1cardButtonType': 'btn-primary',
    	'cal1cardButtonAction': $scope.addAmount}, 
    	{'cal1cardButtonLabel': 'Donate Meal Points', 
    	'cal1cardButton-type': 'btn-default',
    	'cal1cardButtonAction': $scope.donateAmount}];

  });


})(window.angular);
