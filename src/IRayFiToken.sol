//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

interface IRayFiToken {
    function compound(address _staker, uint256 _prismaToCompound) external;

    function getShareholders() external view returns (address[] memory);

    function getStakedBalance(address _user) external view returns (uint256);

    function getTotalStakedAmount() external view returns (uint256);

    function getFeeAmounts()
        external
        view
        returns (
            uint256 buyLiquidityFee,
            uint256 buyTreasuryFee,
            uint256 buyRayFundFee,
            uint256 sellLiquidityFee,
            uint256 sellTreasuryFee,
            uint256 sellRayFundFee
        );
}
