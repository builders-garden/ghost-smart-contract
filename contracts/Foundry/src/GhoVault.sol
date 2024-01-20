// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../src/utils/ERC4626.sol";
import "../src/utils/INonfungiblePositionManager.sol";
import "../src/utils/IUniswapV2Router01.sol";

contract GhostVault is ERC4626, IERC721Receiver {

    address constant USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8; // USDC Sepolia
    address constant GHO = 0xc4bF5CbDaBE595361438F8c6a187bDc330539c60; // GHO Sepolia
    address constant uniswapRouter = 0x49b86914d97Db46FF0F771F7bea4f0B28501605b; // Uniswap Sepolia
    address constant nonfungPositionManager = 0x1238536071E1c677A632429e3655c799b22cDA52; // Uniswap Sepolia

    mapping(address => uint256) public liquidityPositions;
    mapping(address => uint256) public assetsTot;

    uint256 public positionId;
    uint256 public totalLiquidity;
    uint256 public totAssets;

    IERC20 private constant usdc = IERC20(USDC);
    IERC20 private constant gho = IERC20(GHO);

    int24 private constant MIN_TICK = -887272;
    int24 private constant MAX_TICK = -MIN_TICK;
    int24 private constant TICK_SPACING = 60;

    INonfungiblePositionManager public nonfungiblePositionManager =
        INonfungiblePositionManager(0x1238536071E1c677A632429e3655c799b22cDA52); // NonfungiblePositionManager Sepolia
        
    constructor(address _token, string memory name, string memory symbol) ERC4626(IERC20Metadata(_token)) ERC20(name, symbol) {}

    /** @dev See {IERC4626-totalAssets}. */
    function totalAssetsOfUser(address user) public view returns (uint256) {
        return assetsTot[user];
    }
    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view override returns (uint256) {
        return totAssets;
    }


    function deposit(
    uint256 assets,
    address receiver
  ) public override returns (uint256) {
    uint256 maxAssets = maxDeposit(receiver);
    if (assets > maxAssets) {
      revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
    }
    //uint256 shares = previewDeposit(assets);
    SafeERC20.safeTransferFrom(gho, msg.sender, address(this), assets);
    // Swap token on Uniswap
    address[] memory path = new address[](2);
    path[0] = GHO;
    path[1] = USDC;
    uint256 amountToSwap = assets / 2;
    // Approve token to swap
    IERC20(path[0]).approve(uniswapRouter, assets);
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
    uint256 amountAdd0;
    uint256 amountAdd1;
    uint refundUsdc;
    uint refundGho;

    if (liquidityPositions[msg.sender] == 0) {
        // Approve token to swap
        IERC20(path[0]).approve(address(nonfungiblePositionManager), assets);
        // Approve token to swap
        IERC20(path[1]).approve(address(nonfungiblePositionManager), amountOut[1]*2);
        // mint new Uni v3 position
        (positionId, liquidity , amountAdd0, amountAdd1, refundUsdc, refundGho) = mintNewPosition(amountOut[1], amountToSwap);
        liquidityPositions[msg.sender] = positionId;
    } else {
       // Approve token to swap
       IERC20(path[0]).approve(address(nonfungiblePositionManager), assets);
       // Approve token to swap
       IERC20(path[1]).approve(address(nonfungiblePositionManager), amountOut[1]*2);
       // increase liquidity
       (liquidity, , , refundUsdc, refundGho ) = increaseLiquidityCurrentRange(positionId, amountOut[1], amountToSwap);
    }
    
    uint256 shares = liquidity;
    _deposit(_msgSender(), receiver, assets, shares);
    // update liquidity params for view methods
    totalLiquidity += liquidity;
    assetsTot[receiver] += (assets-refundUsdc-refundGho);
    totAssets += (assets-refundUsdc-refundGho);
    return shares;
  }

  function _deposit(
    address caller,
    address receiver,
    uint256 assets,
    uint256 shares
  ) internal override {
    // If _asset is ERC-777, `transferFrom` can trigger a reentrancy BEFORE the transfer happens through the
    // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
    // calls the vault, which is assumed not malicious.
    //
    // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
    // assets are transferred and before the shares are minted, which is a valid state.
    // slither-disable-next-line reentrancy-no-eth
    //SafeERC20.safeTransferFrom(_asset, caller, address(this), assets);
    _mint(receiver, shares);

    emit Deposit(caller, receiver, assets, shares);
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
    ) public returns (uint tokenId, uint128 liquidity, uint amount0, uint amount1, uint refundUsdc, uint refundGho) {

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
            
            uint refund0 = amount0ToAdd - amount0;
            address[] memory path = new address[](2);
            path[0] = USDC;
            path[1] = GHO;
            uint256[] memory amountOut;
            usdc.approve(uniswapRouter, refund0);
            (amountOut) = IUniswapV2Router01(uniswapRouter).swapExactTokensForTokens(
                refund0,
                0,
                path,
                address(this),
                block.timestamp
            );
            gho.transfer(msg.sender, amountOut[1]);
            refundUsdc = amountOut[1];
        }
        if (amount1 < amount1ToAdd) {
            gho.approve(address(nonfungiblePositionManager), 0);
            refundGho = amount1ToAdd - amount1;
            gho.transfer(msg.sender, refundGho);
        }
    }

    function collectAllFees(
        uint tokenId
    ) internal returns (uint amount0, uint amount1) {
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
    ) internal returns (uint128 liquidity, uint amount0, uint amount1, uint refundUsdc, uint refundGho) {
        require(liquidityPositions[msg.sender] != 0, "position does not exist");
       
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

        if (amount0 < amount0ToAdd) {
            
            uint refund0 = amount0ToAdd - amount0;
            address[] memory path = new address[](2);
            path[0] = USDC;
            path[1] = GHO;
            uint256[] memory amountOut;
            usdc.approve(uniswapRouter, refund0);
            (amountOut) = IUniswapV2Router01(uniswapRouter).swapExactTokensForTokens(
                refund0,
                0,
                path,
                address(this),
                block.timestamp
            );
            gho.transfer(msg.sender, amountOut[1]);
            refundUsdc = amountOut[1];
        }
        if (amount1 < amount1ToAdd) {
            gho.approve(address(nonfungiblePositionManager), 0);
            refundGho = amount1ToAdd - amount1;
            gho.transfer(msg.sender, refundGho);
        }
    }

     /** @dev See {IERC4626-withdraw}. */
    function withdraw(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256) {
        
        require(liquidityPositions[msg.sender] != 0, "position does not exist");

        // withdraw from Uniswap
        uint256 amount0;
        uint256 amount1;
        (amount0, amount1) = decreaseLiquidityCurrentRange(liquidityPositions[msg.sender], uint128(shares));

        // collect fees
        uint256 feeAmount0;
        uint256 feeAmount1;
        (feeAmount0, feeAmount1) = collectAllFees(liquidityPositions[msg.sender]);

        //swap to gho
        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = GHO;

        // Approve token to swap
        IERC20(path[0]).approve(uniswapRouter, amount0+feeAmount0);

        

        // Swap token on Uniswap
        uint256[] memory amountOut;
        (amountOut) = IUniswapV2Router01(uniswapRouter).swapExactTokensForTokens(
            IERC20(USDC).balanceOf(address(this)),
            0,
            path,
            address(this),
            block.timestamp
        );
        uint balanceGho = IERC20(GHO).balanceOf(address(this));

        // send to user wallet
        gho.transfer(receiver, balanceGho);

        //uint256 shares = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, shares, shares);
        // update liquidity params for view methods
        assetsTot[owner] -= balanceGho;
        totAssets -= balanceGho;
        totalLiquidity -= shares;
        return shares;
    }
    function _withdraw(
    address caller,
    address receiver,
    address owner,
    uint256 assets,
    uint256 shares
  ) override internal {
    if (caller != owner) {
      _spendAllowance(owner, caller, shares);
    }

    // If _asset is ERC-777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
    // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
    // calls the vault, which is assumed not malicious.
    //
    // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
    // shares are burned and after the assets are transferred, which is a valid state.
    _burn(owner, shares);
    //SafeERC20.safeTransfer(_asset, receiver, assets);

    emit Withdraw(caller, receiver, owner, assets, shares);
  }

    function decreaseLiquidityCurrentRange(
        uint tokenId,
        uint128 liquidity
    ) internal returns (uint amount0, uint amount1) {
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