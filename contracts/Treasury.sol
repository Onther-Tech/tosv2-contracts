// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "./TreasuryStorage.sol";
import "./common/ProxyAccessCommon.sol";

import "./libraries/SafeERC20.sol";
import "./libraries/LibTreasury.sol";

import "./interfaces/ITreasury.sol";
import "./interfaces/ITreasuryEvent.sol";

// import "hardhat/console.sol";

interface IIERC20 {
    function burn(address account, uint256 amount) external returns (bool);
}

interface IITOSValueCalculator {

    function convertAssetBalanceToWethOrTos(address _asset, uint256 _amount)
        external view
        returns (bool existedWethPool, bool existedTosPool,  uint256 priceWethOrTosPerAsset, uint256 convertedAmount);

    function getTOSPricePerETH() external view returns (uint256 price);

    function getETHPricePerTOS() external view returns (uint256 price);
}

interface IIStaking {
    function stakedOfAll() external view returns (uint256) ;
}

interface IIIUniswapV3Pool {
    function liquidity() external view returns (uint128);
}

contract Treasury is
    TreasuryStorage,
    ProxyAccessCommon,
    ITreasury,
    ITreasuryEvent
{
    using SafeERC20 for IERC20;


    constructor() {
    }

    /* ========== onlyPolicyOwner ========== */

    /// @inheritdoc ITreasury
    function enable(
        uint _status,
        address _address
    )
        external override
        onlyPolicyOwner
    {
        LibTreasury.STATUS role = LibTreasury.getSatatus(_status);

        require(role != LibTreasury.STATUS.NONE, "NONE permission");
        require(permissions[role][_address] == false, "already set");

        permissions[role][_address] = true;

        (bool registered, ) = indexInRegistry(_address, role);

        if (!registered) {
            registry[role].push(_address);
        }

        emit Permissioned(_address, _status, true);
    }

    /// @inheritdoc ITreasury
    function disable(uint _status, address _toDisable)
        external override onlyPolicyOwner
    {
        LibTreasury.STATUS role = LibTreasury.getSatatus(_status);
        require(role != LibTreasury.STATUS.NONE, "NONE permission");
        require(permissions[role][_toDisable] == true, "hasn't permissions");

        permissions[role][_toDisable] = false;

        (bool registered, uint256 _index) = indexInRegistry(_toDisable, role);
        if (registered && registry[role].length > 0) {
            if (_index < registry[role].length-1) registry[role][_index] = registry[role][registry[role].length-1];
            registry[role].pop();
        }

        emit Permissioned(_toDisable, uint(role), false);
    }

    /// @inheritdoc ITreasury
    function approve(
        address _addr
    ) external override onlyPolicyOwner {
        tos.approve(_addr, 1e45);
    }

    /// @inheritdoc ITreasury
    function setMR(uint256 _mrRate, uint256 amount) external override onlyPolicyOwner {

        require(mintRate != _mrRate || amount > 0, "check input value");

        require(checkTosSolvencyAfterTOSMint(_mrRate, amount), "unavailable mintRate");

        if (mintRate != _mrRate) mintRate = _mrRate;
        if (amount > 0) tos.mint(address(this), amount);

        emit SetMintRate(_mrRate, amount);
    }

    /// @inheritdoc ITreasury
    function setPoolAddressTOSETH(address _poolAddressTOSETH) external override onlyPolicyOwner {
        require(poolAddressTOSETH != _poolAddressTOSETH, "same address");
        poolAddressTOSETH = _poolAddressTOSETH;

        emit SetPoolAddressTOSETH(_poolAddressTOSETH);
    }

    /// @inheritdoc ITreasury
    function setUniswapV3Factory(address _uniswapFactory) external override onlyPolicyOwner {
        require(uniswapV3Factory != _uniswapFactory, "same address");
        uniswapV3Factory = _uniswapFactory;

        emit SetUniswapV3Factory(_uniswapFactory);
    }

    /// @inheritdoc ITreasury
    function setMintRateDenominator(uint256 _mintRateDenominator) external override onlyPolicyOwner {
        require(mintRateDenominator != _mintRateDenominator && _mintRateDenominator > 0, "check input value");
        mintRateDenominator = _mintRateDenominator;

        emit SetMintRateDenominator(_mintRateDenominator);
    }

    /// @inheritdoc ITreasury
    function addBackingList(address _address)
        public override onlyPolicyOwner
        nonZeroAddress(_address)
    {
        _addBackingList(_address);
    }

    function _addBackingList(address _address) internal
    {
        bool existAsset = false;
        uint256 len = backings.length;

        for (uint256 i = 0; i < len; i++)
            if (_address == backings[i]) {
                existAsset = true;
                break;
            }

        if(!existAsset) {
            backings.push(_address);
            emit AddedBackingList(_address);
        }
    }

    /// @inheritdoc ITreasury
    function deleteBackingList(
        address _address
    )
        external override onlyPolicyOwner
        nonZeroAddress(_address)
    {
        uint256 len = backings.length;

        for (uint256 i = 0; i < len; i++){
            if (_address == backings[i]) {
                if (i < len-1) backings[i] = backings[len-1];
                backings.pop();
                emit DeletedBackingList(_address);
                break;
            }
        }
    }

    /// @inheritdoc ITreasury
    function setFoundationDistributeInfo(
        address[] memory  _addr,
        uint256[] memory _percents
    )
        external override onlyPolicyOwner
    {
        uint256 total = 0;
        require(_addr.length > 0, "zero length");
        require(_addr.length == _percents.length, "wrong length");

        uint256 len = _addr.length;
        for (uint256 i = 0; i< len ; i++){
            require(_addr[i] != address(0), "zero address");
            require(_percents[i] > 0, "zero _percents");
            total += _percents[i];
        }
        require(total < 100, "wrong _percents");

        delete mintings;

        for (uint256 i = 0; i< len ; i++) {
            mintings.push(
                LibTreasury.Minting({
                    mintAddress: _addr[i],
                    mintPercents: _percents[i]
                })
            );
        }

        emit SetFoundationDistributeInfo(_addr, _percents);
    }

    /* ========== permissions : LibTreasury.STATUS.RESERVEDEPOSITOR ========== */

    /// @inheritdoc ITreasury
    function requestMintAndTransfer(
        uint256 _mintAmount,
        address _recipient,
        uint256 _transferAmount,
        bool _distribute
    )
        external override
    {
        require(isBonder(msg.sender), notApproved);

        require(_mintAmount > 0 && _mintAmount >= _transferAmount, "_mintAmount is less than _transferAmount");

        tos.mint(address(this), _mintAmount);

        uint256 remainedAmount = _mintAmount;
        if (_transferAmount > 0) {
            require(_recipient != address(0), "zero recipient");
            remainedAmount = remainedAmount - _transferAmount;
            tos.safeTransfer(_recipient, _transferAmount);
        }

        if(_distribute && remainedAmount > 0) _foundationDistribute(remainedAmount);

        emit RquestedMintAndTransfer(_mintAmount, _recipient, _transferAmount, _distribute);

    }

    /// @inheritdoc ITreasury
    function addBondAsset(address _address)  external override
    {
        require(isBonder(msg.sender), "caller is not bonder");
        require(_address != address(0), "zero asset");
        _addBackingList(_address);
    }

    /// @inheritdoc ITreasury
    function requestTransfer(
        address _recipient,
        uint256 _amount
    ) external override {
        require(isStaker(msg.sender), notApproved);
        require(_recipient != address(0) && _amount > 0, "zero recipient or amount");
        // require(_amount > 0, "zero amount");
        require(tos.balanceOf(address(this)) >= _amount, "treasury balance is insufficient");
        require(tos.transfer(_recipient, _amount), "transfer fail");

        emit RequestedTransfer(_recipient, _amount);
    }


    function _foundationDistribute(uint256 remainedAmount) internal {
        if (mintings.length > 0) {
            for (uint256 i = 0; i < mintings.length ; i++) {
                tos.safeTransfer(
                    mintings[i].mintAddress, remainedAmount *  mintings[i].mintPercents / 100
                );
            }
        }
    }

    /* ========== VIEW ========== */

    /// @inheritdoc ITreasury
    function getMintRate() public override view returns (uint256) {
        return mintRate;
    }

    /// @inheritdoc ITreasury
    function backingRateETHPerTOS() public override view returns (uint256) {
        return (backingReserve() / tos.totalSupply()) ;
    }

    /// @inheritdoc ITreasury
    function indexInRegistry(
        address _address,
        LibTreasury.STATUS _status
    )
        public override view returns (bool, uint256)
    {
        address[] memory entries = registry[_status];
        for (uint256 i = 0; i < entries.length; i++) {
            if (_address == entries[i]) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    /// @inheritdoc ITreasury
    function enableStaking() public override view returns (uint256) {
        return tos.balanceOf(address(this));
    }

    /// @inheritdoc ITreasury
    function backingReserve() public override view returns (uint256) {
        uint256 totalValue = 0;

        bool applyWTON = false;
        uint256 tosETHPricePerTOS = IITOSValueCalculator(calculator).getETHPricePerTOS();
        // console.log("tosETHPricePerTOS %s", tosETHPricePerTOS) ;
        uint256 len = backings.length;
        for(uint256 i = 0; i < len; i++) {

            if (backings[i] == wethAddress)  {
                totalValue += IERC20(wethAddress).balanceOf(address(this));
                applyWTON = true;

            } else if (backings[i] != address(0) && backings[i] != address(tos))  {

                (bool existedWethPool, bool existedTosPool, , uint256 convertedAmount) =
                    IITOSValueCalculator(calculator).convertAssetBalanceToWethOrTos(backings[i], IERC20(backings[i]).balanceOf(address(this)));

                if (existedWethPool) totalValue += convertedAmount;
                else if (existedTosPool){
                    if (poolAddressTOSETH != address(0) && IIIUniswapV3Pool(poolAddressTOSETH).liquidity() == 0) {
                        //  TOS * 1e18 / (TOS/ETH) = ETH
                        totalValue +=  (convertedAmount * mintRateDenominator / mintRate );
                    } else {
                        // TOS * ETH/TOS / token decimal = ETH
                        totalValue += (convertedAmount * tosETHPricePerTOS / 1e18);
                    }
                }
            }
        }

        if (!applyWTON && wethAddress != address(0)) totalValue += IERC20(wethAddress).balanceOf(address(this));

        //0.000004124853366489 ETH/TOS ,  242427 TOS /ETH
        totalValue += address(this).balance;

        // console.log("backingReserve %s", totalValue);

        return totalValue;
    }

    /// @inheritdoc ITreasury
    function totalBacking() public override view returns(uint256) {
         return backings.length;
    }


    /// @inheritdoc ITreasury
    function allBacking() public override view
        returns (address[] memory)
    {
        return backings;
    }

    /// @inheritdoc ITreasury
    function totalMinting() public override view returns(uint256) {
         return mintings.length;
    }

    /// @inheritdoc ITreasury
    function viewMintingInfo(uint256 _index)
        public override view returns(address mintAddress, uint256 mintPercents)
    {
         return (mintings[_index].mintAddress, mintings[_index].mintPercents);
    }

    /// @inheritdoc ITreasury
    function allMintingg() public override view
        returns (
            address[] memory mintAddress,
            uint256[] memory mintPercents
            )
    {
        uint256 len = mintings.length;
        mintAddress = new address[](len);
        mintPercents = new uint256[](len);

        for (uint256 i = 0; i < len; i++){
            mintAddress[i] = mintings[i].mintAddress;
            mintPercents[i] = mintings[i].mintPercents;
        }
    }

    /// @inheritdoc ITreasury
    function hasPermission(uint role, address account) public override view returns (bool) {
        return permissions[LibTreasury.getSatatus(role)][account];
    }

    /// @inheritdoc ITreasury
    function checkTosSolvencyAfterTOSMint(uint256 _checkMintRate, uint256 amount)
        public override view returns (bool)
    {
        if (tos.totalSupply() + amount  <= backingReserve() * _checkMintRate / mintRateDenominator)  return true;
        else return false;
    }

    /// @inheritdoc ITreasury
    function  checkTosSolvency(uint256 amount)
        public override view returns (bool)
    {
        if ( tos.totalSupply() + amount <= backingReserve() * mintRate / mintRateDenominator)  return true;
        else return false;
    }

    /// @inheritdoc ITreasury
    function backingReserveETH() public override view returns (uint256) {
        return backingReserve();
    }

    /// @inheritdoc ITreasury
    function backingReserveTOS() public override view returns (uint256) {

        return backingReserve() * getTOSPricePerETH() / 1e18;
    }

    /// @inheritdoc ITreasury
    function getETHPricePerTOS() public override view returns (uint256) {
        // console.log("getETHPricePerTOS poolAddressTOSETH %s",poolAddressTOSETH);
        // console.log("getETHPricePerTOS liquidity %s",IIIUniswapV3Pool(poolAddressTOSETH).liquidity());
        if (poolAddressTOSETH != address(0) && IIIUniswapV3Pool(poolAddressTOSETH).liquidity() == 0) {
            return  (mintRateDenominator / mintRate);
        } else {
            // console.log("getETHPricePerTOS liquidity is not zero ");
            return IITOSValueCalculator(calculator).getETHPricePerTOS();
        }
    }

    /// @inheritdoc ITreasury
    function getTOSPricePerETH() public override view returns (uint256) {
        if (poolAddressTOSETH != address(0) && IIIUniswapV3Pool(poolAddressTOSETH).liquidity() == 0) {
            return  mintRate;
        } else {
            return IITOSValueCalculator(calculator).getTOSPricePerETH();
        }
    }

    /// @inheritdoc ITreasury
    function isBonder(address account) public override view virtual returns (bool) {
        return permissions[LibTreasury.STATUS.BONDER][account];
    }

    /// @inheritdoc ITreasury
    function isStaker(address account) public override view virtual returns (bool) {
        return permissions[LibTreasury.STATUS.STAKER][account];
    }

    function withdrawEther(address account) external onlyPolicyOwner nonZeroAddress(account) {
        require(address(this).balance > 0, "zero balance");
        payable(account).transfer(address(this).balance);
    }
}
