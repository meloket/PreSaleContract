// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./IDOPool.sol";
import "./IDOStructures.sol";

contract IDOMaster is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;
    
    mapping(uint256 => IDOPool) public idoPools;
    mapping(address => bool) public isExistingPools;
    
    uint256 public totalPools;
    uint256 public feeAmount;

    address payable public feeWallet;
    
    event IDOCreated(address owner, address idoPool,
        uint256 poolIndex,
        string poolName,
        string poolType,
        PoolInfo poolInfo,
        uint256 maxDistributedTokenAmount);
    event FeeAmountUpdated(uint256 newFeeAmount);
    event FeeWalletUpdated(address newFeeWallet);

    constructor(
    ) {
        totalPools = 0;
        //feeAmount = 2 * 10 ** 18;
        feeAmount = 10**17;
        feeWallet = payable(0x6b0C1a8d88d7e72205C253363DA257Ff4548e036);
    }

    function setFeeAmount(uint256 _newFeeAmount) external onlyOwner {
        feeAmount = _newFeeAmount;

        emit FeeAmountUpdated(_newFeeAmount);
    }

    function setFeeWallet(address payable _newFeeWallet) external onlyOwner {
        feeWallet = _newFeeWallet;

        emit FeeWalletUpdated(_newFeeWallet);
    }

    function approve(ERC20 _rewardToken) external onlyOwner{
        _rewardToken.safeApprove(address(this), 1000);
    }

    function increaseAllowance(ERC20 _rewardToken) external onlyOwner{
        _rewardToken.safeIncreaseAllowance(address(this), 1000);
    }

    function createIDO(
        string memory _poolName,
        string memory _poolType,
        PoolInfo memory _poolInfo,
        uint256 _maxDistributedTokenAmount
        // ERC20 _rewardToken
    ) payable external {
        // require( msg.value > feeAmount, "User should pay over than the IDO pool creation fee.");
        // uint256 ethAmount = address(this).balance;
        
        // require(ethAmount < feeAmount, "User should pay over than");

        // if(ethAmount > 10**17){
        //     feeWallet.transfer(ethAmount - 10**17);
        //     (bool trSuccess, ) = feeWallet.call{value: ethAmount - 10**17}("");
        //     require(trSuccess, "Transfer failed.");
        // }
        
        
        // _rewardToken.safeTransferFrom(
        //     msg.sender,
        //     address(this),
        //     1000
        // );

        IDOPool idoPool =
            new IDOPool(
                totalPools,
                _poolName,
                _poolType,
                _poolInfo
            );
        idoPool.transferOwnership(msg.sender);
        
        if(isExistingPools[address(idoPool)] == false){
            idoPools[totalPools] = idoPool;
            totalPools = totalPools + 1;
        }
        
        isExistingPools[address(idoPool)] = true;

        ERC20(_poolInfo.rewardToken).safeTransferFrom(
            msg.sender,
            address(idoPool),
            _maxDistributedTokenAmount
        );
        
        emit IDOCreated(msg.sender, 
                        address(idoPool),
                        totalPools - 1,
                        _poolName,
                        _poolType,
                        _poolInfo,
                        _maxDistributedTokenAmount);
    }

    receive() external payable {}
}