// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LiquidityPool {
    address public token0;
    address public token1;

    uint112 public reserve0;
    uint112 public reserve1;

    constructor(address _t0, address _t1) {
        token0 = _t0;
        token1 = _t1;
    }

    function getReserves() external view returns (uint112, uint112) {
        return (reserve0, reserve1);
    }

    function sync() public {
        reserve0 = uint112(IERC20(token0).balanceOf(address(this)));
        reserve1 = uint112(IERC20(token1).balanceOf(address(this)));
    }

    function getAmountOut(uint256 amountIn, address tokenIn) external view returns (uint256) {
        require(tokenIn == token0 || tokenIn == token1, "bad token");

        uint256 reserveIn = tokenIn == token0 ? reserve0 : reserve1;
        uint256 reserveOut = tokenIn == token0 ? reserve1 : reserve0;

        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }
}
