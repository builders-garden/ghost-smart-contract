// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../src/utils/ERC4626.sol";
import "../src/utils/INonfungiblePositionManager.sol";
import "../src/utils/IUniswapV2Router01.sol";

contract MyERC4626Vault is ERC4626, IERC721Receiver {

    address constant USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8; // USDC Sepolia
    address constant GHO = 0xc4bF5CbDaBE595361438F8c6a187bDc330539c60; // GHO Sepolia
    address constant uniswapRouter = 0x97f6E26dE5aD982eebC54819573156903a1d3024; // Uniswap Sepolia
    address constant nonfungPositionManager = 0x1238536071E1c677A632429e3655c799b22cDA52; // Uniswap Sepolia

    uint256 public positionId;
    uint256 public totalLiquidity;

    IERC20 private constant usdc = IERC20(USDC);
    IERC20 private constant gho = IERC20(GHO);

    int24 private constant MIN_TICK = -887272;
    int24 private constant MAX_TICK = -MIN_TICK;
    int24 private constant TICK_SPACING = 60;

    uint256 public nOfUsers;

    INonfungiblePositionManager public nonfungiblePositionManager =
        INonfungiblePositionManager(0x1238536071E1c677A632429e3655c799b22cDA52); // NonfungiblePositionManager Sepolia
        
    constructor(address _token, string memory name, string memory symbol) ERC4626(IERC20Metadata(_token)) ERC20(name, symbol) {}


    function deposit(
    uint256 assets,
    address receiver
  ) public override returns (uint256) {
    uint256 maxAssets = maxDeposit(receiver);
    if (assets > maxAssets) {
      revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
    }
    uint256 shares = previewDeposit(assets);
    _deposit(_msgSender(), receiver, assets, shares);

    // Swap token on Uniswap
    address[] memory path = new address[](2);
    path[0] = GHO;
    path[1] = USDC;
    uint256 amountToSwap = assets / 2;
    // Approve token to swap
    IERC20(path[0]).approve(uniswapRouter, amountToSwap);
    // Swap token on Uniswap
    uint256[] memory amountOut;
    (amountOut) = IUniswapV2Router01(uniswapRouter).swapExactTokensForTokens(
        amountToSwap,
        0,
        path,
        address(this),
        block.timestamp
    );
    uint256 liquidity;

    if (nOfUsers == 0) {
        // Approve token to swap
        IERC20(path[0]).approve(nonfungPositionManager, amountToSwap);
        // Approve token to swap
        IERC20(path[1]).approve(nonfungPositionManager, amountOut[1]);
        // mint new Uni v3 position
        (positionId, liquidity , , ) = mintNewPosition(amountOut[1], amountToSwap);
    } else {
       // Approve token to swap
       IERC20(path[0]).approve(nonfungPositionManager, amountToSwap);
       // Approve token to swap
       IERC20(path[1]).approve(nonfungPositionManager, amountToSwap);
       // increase liquidity
       (liquidity, , ) = increaseLiquidityCurrentRange(positionId, amountOut[1], amountToSwap);
    }
    totalLiquidity += liquidity;
    nOfUsers += 1;
    return shares;
  }


    function onERC721Received(
        address operator,
        address from,
        uint tokenId,
        bytes calldata
    ) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function mintNewPosition(
        uint amount0ToAdd,
        uint amount1ToAdd
    ) public returns (uint tokenId, uint128 liquidity, uint amount0, uint amount1) {
        usdc.transferFrom(msg.sender, address(this), amount0ToAdd);
        gho.transferFrom(msg.sender, address(this), amount1ToAdd);

        usdc.approve(address(nonfungiblePositionManager), amount0ToAdd);
        gho.approve(address(nonfungiblePositionManager), amount1ToAdd);

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: USDC,
                token1: GHO,
                fee: 3000,
                tickLower: (MIN_TICK / TICK_SPACING) * TICK_SPACING,
                tickUpper: (MAX_TICK / TICK_SPACING) * TICK_SPACING,
                amount0Desired: amount0ToAdd,
                amount1Desired: amount1ToAdd,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            });

        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(
            params
        );

        if (amount0 < amount0ToAdd) {
            usdc.approve(address(nonfungiblePositionManager), 0);
            uint refund0 = amount0ToAdd - amount0;
            usdc.transfer(msg.sender, refund0);
        }
        if (amount1 < amount1ToAdd) {
            gho.approve(address(nonfungiblePositionManager), 0);
            uint refund1 = amount1ToAdd - amount1;
            gho.transfer(msg.sender, refund1);
        }
    }

    function collectAllFees(
        uint tokenId
    ) external returns (uint amount0, uint amount1) {
        INonfungiblePositionManager.CollectParams
            memory params = INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (amount0, amount1) = nonfungiblePositionManager.collect(params);
    }

    function increaseLiquidityCurrentRange(
        uint tokenId,
        uint amount0ToAdd,
        uint amount1ToAdd
    ) public returns (uint128 liquidity, uint amount0, uint amount1) {
        usdc.transferFrom(msg.sender, address(this), amount0ToAdd);
        gho.transferFrom(msg.sender, address(this), amount1ToAdd);

        usdc.approve(address(nonfungiblePositionManager), amount0ToAdd);
        gho.approve(address(nonfungiblePositionManager), amount1ToAdd);

        INonfungiblePositionManager.IncreaseLiquidityParams
            memory params = INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amount0ToAdd,
                amount1Desired: amount1ToAdd,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        (liquidity, amount0, amount1) = nonfungiblePositionManager.increaseLiquidity(
            params
        );
    }

    function decreaseLiquidityCurrentRange(
        uint tokenId,
        uint128 liquidity
    ) public returns (uint amount0, uint amount1) {
        INonfungiblePositionManager.DecreaseLiquidityParams
            memory params = INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(params);
    }

}