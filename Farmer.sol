// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";

interface cToken {
    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);
    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint);
    function liquidateBorrow(address borrower, uint repayAmount, CTokenInterface cTokenCollateral) external returns (uint);
    function sweepToken(EIP20NonStandardInterface token) external;
}

interface AurigamiComptroller {
    function enterMarkets(address[] memory auTokens) external;
}

interface TriBar {
    function enter(uint256 _triAmount) external;
    function leave(uint256 xTriAmount) external;
    function balanceOf(address account) external view returns (uint256);
}

interface TriRouter {
     function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

interface TriFlashSwap {
    function swap(
        uint8 tokenIndexFrom,
        uint8 tokenIndexTo,
        uint256 dx,
        uint256 minDy,
        uint256 deadline
    )
        external
        returns (uint256);
}

contract Farmer {

    // Admin of the contract
    address public admin;
    // Address of main liquid staking contract
    address public main;
    // Reward tokens
    IERC20 public constant BSTN = IERC20(0x9f1F933C660a1DC856F0E0Fe058435879c5CCEf0);
    IERC20 public constant PLY = IERC20(0x09C9D464b58d96837f8d8b6f4d9fE4aD408d3A4f);
    IERC20 public constant TRI = IERC20(0xFa94348467f64D5A457F75F8bc40495D33c65aBB);
    IERC20 public constant USN = IERC20(0x5183e1B1091804BC2602586919E6880ac1cf2896);

    // Where we will be farming rewards
    cToken public constant cBSTN = cToken(0x08Ac1236ae3982EC9463EfE10F0F320d9F5A9A4b);
    cToken public constant cPLY = cToken(0xC9011e629c9d0b8B1e4A2091e123fBB87B3A792c);
    cToken public constant cBTC = cToken(0xCFb6b0498cb7555e7e21502E0F449bf28760Adbb);
    TriBar public constant bar = TriBar(0x802119e4e253D5C19aA06A5d567C5a41596D6803);

    // All USN shall be converted to BTC because BTC > fiat
    IERC20 public constant BTC = IERC20(0xF4eB217Ba2454613b15dBdea6e5f22276410e89e);
    IERC20 public constant USDC = IERC20(0xB12BFcA5A55806AaF64E99521918A4bf0fC40802);
    IERC20 public constant WNEAR = IERC20(0xC42C30aC6Cc15faC9bD938618BcaA1a1FaE8501d);

    // Address of aurigami comptroller
    AurigamiComptroller public constant troller = AurigamiComptroller(0x817af6cfAF35BdC1A634d6cC94eE9e4c68369Aeb);

    // Routes for trading between BTC & USDC
    address[] public constant USDCtoBTC = [USDC, WNEAR, BTC];
    address[] public constant BTCtoUSDC = [BTC, WNEAR, USDC];
    
    // Trisolaris routers
    TriRouter public router = TriRouter(0x2CB45Edb4517d5947aFdE3BEAbF95A582506858B);
    TriFlashSwap public flashSwap = TriFlashSwap(0x458459e48dbac0c8ca83f8d0b7b29fefe60c3970);

    // Only admin can access
    modifier onlyAdmin {
        require(msg.sender == admin, "ONLY ADMIN CAN CALL");
        _;
    }

    // =====================================
    //            CONSTRUCTOR
    // =====================================

    // @param _admin Admin address
    // @param _stAurora Staked aurora address
    constructor( address _admin) {
        admin = _admin;
        BSTN.approve(address(cBSTN), 2**256 - 1);
        PLY.approve(address(cPLY), 2**256 - 1);
        TRI.approve(address(bar), 2**256 - 1);
        USDC.approve(address(router), 2**256 - 1);
        USDC.approve(address(flashSwap), 2**256 - 1);
        BTC.approve(address(router), 2**256 - 1);
        BTC.approve(address(cBTC), 2**256 - 1);
        USN.approve(address(flashSwap), 2**256 - 1);
    }

    // @notice Put funds to work
    function putFundsToWork() external {
        uint256 BSTNBal = BSTN.balanceOf(address(this));
        uint256 PLYBal = PLY.balanceOf(address(this));
        uint256 TriBal = TRI.balanceOf(address(this));
        cBSTN.mint(BSTNBal);
        cPLY.mint(PLYBal);
        bar.enter(TriBal);
    }
    
    // @notice Withdraws all funds
    function withdrawRewards() external onlyAdmin {
        uint256 cBSTNBal = cBSTN.balanceOf(address(this));
        uint256 cPLYBal = cPLY.balanceOf(address(this));
        uint256 xTRiBAl = bar.balanceOf(address(this));
        cBSTN.redeem(cBSTNBal);
        cPLY.redeem(cPLYBal);
        bar.leave(xTriBal);
    }
    
    // @notice Sends all funds back to main contract
    function sendRewardsBack() external onlyAdmin {
        uint256 BSTNBal = BSTN.balanceOf(address(this));
        uint256 PLYBal = PLY.balanceOf(address(this));
        uint256 TriBal = TRI.balanceOf(address(this));
        uint256 USN = USN.balanceOf(address(this));
        uint256 BTC = BTC.balanceOf(address(this));
        BSTN.transfer(main, BSTNBal);
        PLY.transfer(main, PLYBal);
        TRI.transfer(main, TriBal);
        USN.transfer(main, USNbal);
        BTC.transfer(main, BTCBal);
    }

    // @notice Allows admin to swap USN for BTC
    // @dev Reason for caller restriction is to avoid slippage attacks
    function deployUSN() external onlyAdmin {
        uint256 USNbal = USN.balanceOf(address(this));
        flashSwap.swap(
            2,
            0,
            USNBal,
            0,
            block.timestamp.add(60)
        );
        uint256 USDCBal = USDC.balanceOf(address(this));
        router.swapExactTokensForTokens(
            USDCBal,
            0,
            USDCtoBTC,
            address(this),
            block.timestamp.add(60)
        );
    }

    // @notice Allows admin to deposit BTC as collateral and withdraw another token
    // @param _cToken Address of cToken to borrow
    // @param _borrowToken Underlying token
    // @param _borrowAmount Amount to borrow
    // @param _helper Person receiving borrowed tokens
    function depositBTCandBorrow(
        address _cToken, 
        address _borrowToken, 
        uint256 _borrowAmount, 
        address _helper
    ) external onlyAdmin {
        uint256 BTCBal = BTC.balanceOf(address(this));
        cBTC.mint(BTCBal);

        address[] markets = new address[](2);
        markets[0] = cBTC;
        markets[1] = cPLY;
        troller.enterMarkets(markets);

        cToken(_cToken).borrow(_borrowAmount);
        uint256 balance = IERC20(_borrowToken).balanceOf(address(this));
        IERC20(_borrowToken).transfer(_helper, balance);
    }

    // @notice Allows admin to repay debt and withdraw BTC collateral
    // @param _cToken Address of cToken to borrow
    // @param _borrowToken Underlying token
    function repayAndWithdraw(
        address _cToken, 
        address _borrowToken
    ) external onlyAdmin {
        IERC20(_borrowToken).approve(_cToken, 2**256 - 1);
        uint256 balance = IERC20(_borrowToken).balanceOf(address(this));
        cToken(_cToken).repayBorrow(balance);
        uint256 cBTCBal = cBTC.balanceOf(address(this));
        cBTC.redeem(cBTCBal);
    }

    // @notice Allows admin to set the address of the main contract
    function setMainContract(address _contract) external onlyAdmin {
        main = _contract;
    }
}
