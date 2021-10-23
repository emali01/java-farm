// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IMasterBrew {
    function deposit(uint256 _pid, uint256 _amount, address _referrer) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function pendingJava(uint256 _pid, address _user) external view returns (uint256);

    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);

    function emergencyWithdraw(uint256 _pid) external;

    function referralCommissionRate() external view returns (uint16);
}