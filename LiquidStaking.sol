// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";

interface IFarmer {
    function putFundsToWork() external;
}

interface AuroraStaking {
    function stake(uint256 amount) external;
    function unstakeAll() external;
    function withdraw(uint256 streamId) external;
    function moveAllRewardsToPending() external;
    function withdrawAll() external;
    function getUserTotalDeposit(address account) external;
}

/// @title Aurora Liquid Staking Contract
/// @author Lance Henderson
/// 
/// @notice Contract allows user to stake their aurora tokens.
/// In return they receive an ERC20 receipt (stAurora)
/// The reason for this is so users can gain immediate liquidity 
/// from their staked aurora (by selling on the open market) rather 
/// than having to wait 2 days
/// 
/// @dev Important things to note:
/// - The user is not able to redeem their stAurora (only sell it)
/// - The rewards generated from streams are sent to a separate contract
/// - This separate contract will earn a yield on these tokens
/// - Only the admin can withdraw the aurora tokens
/// - The stAurora will become redeemable for aurora/rewards once/6 months
/// Reasoning behind this is that rewards will be put in complex strategies,
/// hence we don't want to be unwinding complex positions constantly.

contract AuroraLiquidStaking is ERC20 {

    // Admin of the contract
    address public admin;
    // Aurora Token
    IERC20 public constant aurora = IERC20(0x8BEc47865aDe3B172A928df8f990Bc7f2A3b9f79);
    // Aurora Staking Contract
    AuroraStaking public staking = AuroraStaking(0xccc2b1aD21666A5847A804a73a41F904C4a4A0Ec);
    // Array of reward tokens
    IERC20[] public rewardStreamTokens;
    // Contract which will handle farming with harvested rewards
    IFarmer public farmer;

    // Only admin can access
    modifier onlyAdmin {
        require(msg.sender == admin, "ONLY ADMIN CAN CALL");
        _;
    }


    // =====================================
    //            CONSTRUCTOR
    // =====================================

    constructor(
        address[] _tokens,
        address _admin
    ) ERC20("Staked Aurora", "stAurora") 
    {
        admin = _admin;

        uint256 length = _tokens.length();
        for(uint i; i < length; ++i) {
            rewardStreamTokens[i] = IERC20(_tokens[i]);
        }
    }

    // =====================================
    //             EXTERNAL
    // =====================================

    // @notice Allows user to stake their aurora 
    // @dev User receives an ERC20 token receipt (stAurora)
    // @param _amount Amount of aurora to stake
    function deposit(uint256 _amount) public {
        aurora.transferFrom(msg.sender, address(this), _amount);
        uint256 totalAurora = staking.getUserTotalDeposit(address(this));
        uint256 mintAmount = _amount / totalAurora * totalSupply();
        _mint(msg.sender, mintAmount);
    }

    // @notice Helper function to stake all of user's aurora balance
    function depositAll() external {
        uint256 auroraBalance = aurora.balanceOf(msg.sender);
        deposit(auroraBalance);
    }

    // =====================================
    //             HELPER
    // =====================================

    // @notice Moves rewards to pending (become accessible after 2 days)
    function moveRewardsToPending() external {
        staking.moveAllRewardsToPending();
    }

    // @notice Harvest rewards and puts them to work (ie staking)
    // @dev Farming with received rewards will be delegated to a separate contract
    function harvest() external {
        staking.withdrawAll();
        uint256 length = rewardStreamTokens.length();
        for(uint i; i < length; ++i) {
            uint256 tokenBalance = rewardStreamTokens[i].balanceOf(address(this));
            rewardStreamTokens[i].transfer(farmer, tokenBalance);
        }
        farmer.putFundsToWork();
    }

    // ====================================
    //              ADMIN
    // ====================================
    
    // @notice In the edge case that something goes wrong, 
    // the admin is able to recover funds.
    function emergencyUnstake() external onlyAdmin {
        staking.unstakeAll();
    }

    // @notice Funds can only be withdrawn after a 2 day wait.
    function emergencyWithdraw() external onlyAdmin {
        staking.withdraw(0);
        uint256 balance = aurora.balanceOf(address(this));
        aurora.transfer(msg.sender, balance);
    }

    // @notice Allows admin to change farmer contract
    // @param _farmer Address of new farmer
    function setFarmerContract(address _farmer) external onlyAdmin {
        farmer = IFarmer(_farmer);
    }

    // @notice Allows admin to add reward token
    // @param _reward Address of reward token
    function addRewardToken(address _reward) external onlyAdmin {
        rewardStreamTokens.push(IERC20(_reward));
    } 
     
    // @notice Allows admin to remove reward token
    // @param _index Index of reward token to remove
    function removeRewardToken(uint256 _index) external onlyAdmin {
        delete rewardStreamTokens[index];
    }
    
    // @notice Allows admin to withdraw a token
    // @param _token Token to withdraw
    function sweepTokens(uint256 _token) external onlyAdmin {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(msg.sender, balance);
    }

}
