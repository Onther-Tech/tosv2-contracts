// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

/// @title LibBondDepositoryV1_5
library LibBondDepositoryV1_5
{

    // market market info
    struct MarketInfo {
        uint8 bondType;
        uint32 startTime;
        bool closed;
        uint256 capacityUpdatePeriod;
        uint256 totalSold;
    }

    struct BonusRateInfo {
        address bonusRatesAddress;
        uint256 bonusRatesId;
    }

}