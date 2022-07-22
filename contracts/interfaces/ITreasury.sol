// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.7.5;

import "../libraries/LibTreasury.sol";

interface ITreasury {


    /* ========== onlyPolicyOwner ========== */
    // 주소에 권한설정
    function enable(uint _status,  address _address) external ;

    // 주소에 권한설정
    function disable(uint _status, address _toDisable) external;

    // 토큰 사용 승인, ( 스테이킹 컨트랙에 승인을 한다.)
    function approve(address _addr) external ;

    //  민팅 비율
    function setMR(uint256 _mrRate, uint256 amount) external;

    // 특정 ERC20 자산에 대한 mintRate이 있을 가능성이 있다.
    function setMROfAddress(address _asset, uint256 _mrRate) external;

    function addBackingList(address _address, address _tosPooladdress, uint24 _fee) external ;
    function deleteBackingList(address _address) external;

    // 토큰아이디 등록
    // function addLiquidityIdList(uint256 _tokenId, address _tosPoolAddress) external ;


    function setFoundationDistributeInfo(
        address[] memory  _addr,
        uint256[] memory _percents
    ) external ;


    /* ========== onlyOwner ========== */

    function requestMintAndTransfer(uint256 _mintAmount, address _recipient, uint256 _transferAmount, bool _distribute) external ;

    /* ========== onlyStaker ========== */

    function requestTrasfer(address _recipient, uint256 _amount)  external;

    /* ========== Anyone can execute ========== */

    function deposit(
        uint256 _amount,
        address _token,
        address _tosERC20Pool,
        uint24 _fee,
        uint256 _profit
    ) external returns (uint256);

    function withdraw(
        uint256 _amount,
        address _token,
        address _tosERC20Pool,
        uint24 _fee
    ) external;

    // function mint(address _recipient, uint256 _amount) external;

    // function backingUpdate() external;

    /* ========== VIEW ========== */
    function backingRateETHPerTOS() external view returns (uint256);

    function indexInRegistry(address _address, LibTreasury.STATUS _status) external view returns (bool, uint256);

    function enableStaking() external view returns (uint256);
    function backingReserve() external view returns (uint256) ;

    function totalBacking() external view returns (uint256);

    function viewBackingInfo(uint256 _index)
        external view
        returns (address erc20Address, address tosPoolAddress, uint24 fee);

    function allBacking() external view returns (
        address[] memory erc20Address,
        address[] memory tosPoolAddress,
        uint24[] memory fee
    );

    function totalMinting() external view returns(uint256) ;
    function viewMintingInfo(uint256 _index)
        external view returns(address mintAddress, uint256 mintPercents);

    function allMintingg() external view
        returns (
            address[] memory mintAddress,
            uint256[] memory mintPercents
            );

    function hasPermission(LibTreasury.STATUS role, address account) external view returns (bool);
    function hasPermission(uint role, address account) external view returns (bool);

}
