// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./IDOStructures.sol";

interface IPancakeSwapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IPancakeSwapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
}

contract IDOPool is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;
    
    uint256 public poolIndex;
    string public poolName;
    string public poolType;
    
    IPancakeSwapV2Router02 private pancakeV2Router; // pancakeswap v2 router
    address private pancakeV2Pair; // pancakeswap v2 pair
    
    uint256 public tokensForDistribution;
    uint256 public distributedTokens;
    
    uint256 public liquidityETH;
    uint256 public liquidityToken;
    
    PoolInfo public poolInfo;
    StatusInfo public status;
    mapping(address => UserInfo) public userInfo;
    
    bool public success;
    bool public saleEnd;
    bool public openRefund;
    
    event TokensDebt(
        address indexed holder,
        uint256 ethAmount,
        uint256 tokenAmount
    );
    event TokensWithdrawn(address indexed holder, uint256 amount);

    constructor(
        uint256 _poolIndex,
        string memory _poolName,
        string memory _poolType,
        PoolInfo memory _poolInfo
    ) {
        // poolIndex = 1;
        // poolName = "Test Pool";
        // poolType = "Test";
        poolIndex = _poolIndex;
        poolName = _poolName;
        poolType = _poolType;
        
        poolInfo = _poolInfo;

        require(
            _poolInfo.startTimestamp > block.timestamp,
            "Start timestamp must be more than current block"
        );
        
        require(
            _poolInfo.startTimestamp < _poolInfo.finishTimestamp,
            "Start timestamp must be less than finish timestamp"
        );
        
        require(
            _poolInfo.softEthCap > 0,
            "Soft capital must be more than 0"
        );
        
        require(
            _poolInfo.softEthCap < _poolInfo.hardEthCap,
            "Soft capital must be less than hard capital"
        );
        
        success = false;
        saleEnd = false;
        openRefund = false;
    }
    
    modifier checkPresale() {
        if(block.timestamp > poolInfo.startTimestamp){
            status.started = true;
        }
        
        uint256 ethAmount = address(this).balance;
        
        if(ethAmount >= poolInfo.softEthCap){
            success = true;
        }
        
        if( ethAmount >= poolInfo.hardEthCap){
            status.filled = true;
        }
        
        if(block.timestamp >= poolInfo.finishTimestamp){
            if(ethAmount < poolInfo.softEthCap){
                openRefund = true;
            }
            status.started = false;
            status.ended = true;
        }
        
        if(ethAmount > poolInfo.hardEthCap || block.timestamp >= poolInfo.finishTimestamp){
            addLiquidity(liquidityETH, liquidityToken);
            // pancakeswap addition,
            saleEnd = true;
        }
        
        _;
    }

    function pay() payable external checkPresale {
        require(block.timestamp >= poolInfo.startTimestamp, "Not started");
        require(block.timestamp < poolInfo.finishTimestamp, "Ended");

        require(msg.value >= poolInfo.minEthPayment, "Less then min amount");
        require(msg.value <= poolInfo.maxEthPayment, "More then max amount");
        
        require(openRefund == false, "Sale must not be refund mode");
        require(saleEnd == false, "Sale must be open");
        
        uint256 ethAmount = address(this).balance;
        require(ethAmount <= poolInfo.hardEthCap, "HardCap Overfilled");

        UserInfo storage user = userInfo[msg.sender];
        require(user.totalInvestedETH.add(msg.value) <= poolInfo.maxEthPayment, "More then max amount");

        uint256 tokenAmount = getTokenAmount(msg.value);
        tokensForDistribution = tokensForDistribution.add(tokenAmount);
        
        user.totalInvestedETH = user.totalInvestedETH.add(msg.value);
        user.total = user.total.add(tokenAmount);
        user.debt = user.debt.add(tokenAmount);
        
        emit TokensDebt(msg.sender, msg.value, tokenAmount);
    }

    function getTokenAmount(uint256 ethAmount)
        internal
        view
        returns (uint256)
    {
        uint256 decimals =  ERC20(poolInfo.rewardToken).decimals();
        return ethAmount.mul(10**decimals).div(poolInfo.tokenPrice);
    }

    /// @dev Allows to claim tokens for the specific user.
    /// @param _user Token receiver.
    function claimFor(address _user) external {
        proccessClaim(_user);
    }

    /// @dev Allows to claim tokens for themselves.
    function claim() external {
        proccessClaim(msg.sender);
    }

    /// @dev Proccess the claim.
    /// @param _receiver Token receiver.
    function proccessClaim(
        address _receiver
    ) internal nonReentrant{
        require(success == true, "Sale must be successed");
        require(saleEnd == true, "Sale must be finished");

        UserInfo storage user = userInfo[_receiver];
        uint256 _amount = user.debt;
        if (_amount > 0) {
            user.debt = 0;            
            distributedTokens = distributedTokens.add(_amount);
            ERC20(poolInfo.rewardToken).safeTransfer(_receiver, _amount);
            emit TokensWithdrawn(_receiver,_amount);
        }
    }

    function refund(address _user) external {
        processRefund(_user);
    }
    
    function processRefund(
        address _receiver
    ) internal nonReentrant {
        require(success == false, "Presale failed");
        require(openRefund == true, "Pool need to open refund");
        
        UserInfo storage user = userInfo[_receiver];
        uint256 fee = user.totalInvestedETH.mul(8).div(100);
        uint256 _amount = user.totalInvestedETH - fee;
        
        (bool trSuccess, ) = msg.sender.call{value: _amount}("");
        require(trSuccess, "Transfer failed.");
    }

    function withdrawETH(uint256 amount) external onlyOwner {
        (bool trSuccess, ) = msg.sender.call{value: amount}("");
        require(trSuccess, "Transfer failed.");
    }

    function withdrawNotSoldTokens(address _receiver) external onlyOwner {
        require(block.timestamp > poolInfo.finishTimestamp, "Withdraw allowed after stop accept ETH");
        
        uint256 balance = ERC20(poolInfo.rewardToken).balanceOf(address(this));
        ERC20(poolInfo.rewardToken).safeTransfer(_receiver, balance.add(distributedTokens).sub(tokensForDistribution));
    }
    
    function cancelPool() external onlyOwner{
        success = false;
        saleEnd = true;
        openRefund = true;
        status.cancelled = true;
    }
    
    function getPoolInfo() public view returns(PoolInfo memory){
        return poolInfo;
    }
    
    function addLiquidity(uint256 ethAmount, uint256 tokenAmount) internal {
        pancakeV2Router = IPancakeSwapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E); // mainnet Router address
        
        ERC20(poolInfo.rewardToken).approve(address(pancakeV2Router), tokenAmount);
        
        pancakeV2Pair = IPancakeSwapV2Factory(pancakeV2Router.factory()).createPair(address(poolInfo.rewardToken), pancakeV2Router.WETH());
        
        pancakeV2Router.addLiquidityETH{value: ethAmount}(address(poolInfo.rewardToken), tokenAmount, 0, 0, owner(), block.timestamp);
        
        ERC20(pancakeV2Pair).approve(address(pancakeV2Router),type(uint256).max);
    }
    
    function setliquidityETH(uint256 _newETHAmount) external onlyOwner {
        liquidityETH = _newETHAmount;
    }
    
    function setliquidtyToken(uint256 _newTokenAmount) external onlyOwner {
        liquidityToken = _newTokenAmount;
    }

    function setVoting(bool isVote)external onlyOwner{
        status.voting = isVote;
    }
    
    function setCertified(bool isCertified)external onlyOwner{
        status.certified = isCertified;
    }
    
    function setPoolInfo(PoolInfo memory _poolInfo)external onlyOwner{
        poolInfo = _poolInfo;
    }

    receive() external payable {}
}