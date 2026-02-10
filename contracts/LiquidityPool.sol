// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";  

interface IERC20Like { 
    function balanceOf(address) external view returns (uint256);
}

contract LiquidityPool is ERC20 {
    using SafeERC20 for IERC20;

    address public token0;
    address public token1;

    uint112 public reserve0;
    uint112 public reserve1;

    event Sync(uint112 reserve0, uint112 reserve1);

    constructor(address _token0, address _token1) ERC20("LP Token", "LPT") {
        require(_token0 != address(0) && _token1 != address(0), "zero");
        require(_token0 != _token1, "same");
        token0 = _token0;
        token1 = _token1;
    }

    function _update(uint256 bal0, uint256 bal1) internal {
        require(bal0 <= type(uint112).max && bal1 <= type(uint112).max, "overflow");
        reserve0 = uint112(bal0);
        reserve1 = uint112(bal1);
        emit Sync(reserve0, reserve1);
    }

    function sync() external {
        uint256 bal0 = IERC20Like(token0).balanceOf(address(this));
        uint256 bal1 = IERC20Like(token1).balanceOf(address(this));
        _update(bal0, bal1);
    }

    // Остальные функции (mint/burn/swap) оставь как в твоей текущей версии,
    // добавив только sync() и event Sync, и вызов _update должен эмитить Sync.
}
