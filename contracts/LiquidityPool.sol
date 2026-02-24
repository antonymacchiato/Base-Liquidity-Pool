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

    event Mint(address indexed sender, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(address indexed sender, uint256 amountIn0, uint256 amountIn1, uint256 amountOut0, uint256 amountOut1, address indexed to);
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor(address _token0, address _token1) ERC20("LP Token", "LPT") {
        require(_token0 != address(0) && _token1 != address(0), "zero");
        require(_token0 != _token1, "same");
        token0 = _token0;
        token1 = _token1;
    }

    function getReserves() external view returns (uint112, uint112) {
        return (reserve0, reserve1);
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

    // Improvement
    function skim(address to) external {
        require(to != address(0), "to=0");
        uint256 bal0 = IERC20Like(token0).balanceOf(address(this));
        uint256 bal1 = IERC20Like(token1).balanceOf(address(this));

        uint256 extra0 = bal0 > reserve0 ? bal0 - reserve0 : 0;
        uint256 extra1 = bal1 > reserve1 ? bal1 - reserve1 : 0;

        if (extra0 > 0) IERC20(token0).safeTransfer(to, extra0);
        if (extra1 > 0) IERC20(token1).safeTransfer(to, extra1);
    }

    function mint(address to) external returns (uint256 liquidity) {
        uint256 bal0 = IERC20Like(token0).balanceOf(address(this));
        uint256 bal1 = IERC20Like(token1).balanceOf(address(this));
        uint256 amount0 = bal0 - reserve0;
        uint256 amount1 = bal1 - reserve1;
        require(amount0 > 0 && amount1 > 0, "no amounts");

        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1);
            require(liquidity > 0, "liquidity=0");
        } else {
            liquidity = Math.min((amount0 * _totalSupply) / reserve0, (amount1 * _totalSupply) / reserve1);
        }

        _mint(to, liquidity);
        _update(bal0, bal1);
        emit Mint(msg.sender, amount0, amount1, liquidity);
    }

    function burn(address to) external returns (uint256 amount0, uint256 amount1) {
        uint256 bal0 = IERC20Like(token0).balanceOf(address(this));
        uint256 bal1 = IERC20Like(token1).balanceOf(address(this));

        uint256 liquidity = balanceOf(address(this));
        require(liquidity > 0, "no LP sent");

        uint256 _totalSupply = totalSupply();
        amount0 = (liquidity * bal0) / _totalSupply;
        amount1 = (liquidity * bal1) / _totalSupply;
        require(amount0 > 0 && amount1 > 0, "amount=0");

        _burn(address(this), liquidity);

        IERC20(token0).safeTransfer(to, amount0);
        IERC20(token1).safeTransfer(to, amount1);

        bal0 = IERC20Like(token0).balanceOf(address(this));
        bal1 = IERC20Like(token1).balanceOf(address(this));
        _update(bal0, bal1);

        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(uint256 amountOut0, uint256 amountOut1, address to) external {
        require(amountOut0 > 0 || amountOut1 > 0, "out=0");
        require(to != address(0), "to=0");
        require(amountOut0 < reserve0 && amountOut1 < reserve1, "insufficient reserves");

        if (amountOut0 > 0) IERC20(token0).safeTransfer(to, amountOut0);
        if (amountOut1 > 0) IERC20(token1).safeTransfer(to, amountOut1);

        uint256 bal0 = IERC20Like(token0).balanceOf(address(this));
        uint256 bal1 = IERC20Like(token1).balanceOf(address(this));

        uint256 amountIn0 = bal0 > (reserve0 - amountOut0) ? bal0 - (reserve0 - amountOut0) : 0;
        uint256 amountIn1 = bal1 > (reserve1 - amountOut1) ? bal1 - (reserve1 - amountOut1) : 0;
        require(amountIn0 > 0 || amountIn1 > 0, "in=0");

        uint256 bal0Adj = (bal0 * 1000) - (amountIn0 * 3);
        uint256 bal1Adj = (bal1 * 1000) - (amountIn1 * 3);
        require(bal0Adj * bal1Adj >= uint256(reserve0) * uint256(reserve1) * 1000 * 1000, "K");

        _update(bal0, bal1);
        emit Swap(msg.sender, amountIn0, amountIn1, amountOut0, amountOut1, to);
    }
    address public feeTo;

function setFeeTo(address _feeTo) external onlyOwner {
    feeTo = _feeTo;
    }

function claimProtocolFees(address token) external {
    require(msg.sender == feeTo, "not feeTo");
    uint256 bal = IERC20(token).balanceOf(address(this));
    IERC20(token).transfer(feeTo, bal);
    }
}
