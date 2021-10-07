// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

struct PoolInfo {
    address rewardToken;
    uint256 tokenPrice;
    uint256 startTimestamp;
    uint256 finishTimestamp;
    uint256 minEthPayment;
    uint256 maxEthPayment;
    uint256 softEthCap;
    uint256 hardEthCap;
}

struct UserInfo {
    uint debt;
    uint total;
    uint totalInvestedETH;
}

struct StatusInfo {
    bool started;
    bool ended;
    bool certified;
    bool voting;
    bool filled;
    bool cancelled;
}