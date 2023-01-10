// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IDepositContract.sol";

/**
 * @title
 * @authors
 */
library StakingContractLibrary {
    struct SellStruct{
        uint256 amount;
        uint256 price;
    }

    enum Status {
        Depositing,
        Ready_To_Invest,
        Investing,
        Claiming,
        Withdrawing,
        Refunding,
        Expired
    }

    //*************************Helpers*************************//

    /**
     * @notice   This function give the number of days elapsed since the timestamp given in parameter
     * @dev      In this function we are
     * @param    _timestamp the starting time
     * @return   uint the elsaped days
     */
    function elapsedTimeSince(uint256 _timestamp)
        public
        view
        returns (uint256)
    {
        return convertSecondsToDays(block.timestamp - _timestamp);
    }

    /** 
    * @notice   This function will be use to convert seconds number to days.
                It is usefull because our timer only takes seconds.
    * @dev      In this method we are simply divising seconds number by 86400 because there are 86400 seconds per day
    * @param    _seconds a number of seconds
    * @return    uint the seconds number converted to days
    */
    function convertSecondsToDays(uint256 _seconds)
        public
        pure
        returns (uint256)
    {
        return _seconds / 86400; // 86400 seconds = 1 day
    }

    /** 
    * @notice   This function will be use to convert days number to seconds.
                It is usefull because our timer only takes seconds.
    * @dev      In this method we are simply multiplying days number by 86400 because there are 86400 seconds per day
    * @param    _daysNumber a number of days
    * @return    uint the days number converted to seconds
    */
    function convertDaysToSeconds(uint256 _daysNumber)
        public
        pure
        returns (uint256)
    {
        return _daysNumber * 86400; // 1 day = 86400 seconds
    }

    /**
     * @notice   This function will return the total amount to return to the user and the end of the timer
     * @dev      We are multiplying the deposit amount by the divisor and adding it to the previously calculated return amount
     * @param    _returnAmount the previously calculated return amount
     * @param    _depositAmount the user deposit amount
     * @return    totalReturn the total to be returned to the user
     */
    function calculateTotalReturn(
        uint256 _returnAmount,
        uint256 _depositAmount
    ) public pure returns(uint256) {
        return (_returnAmount + (_depositAmount * 10000000)) / 10000000;
    }

    /**
     * @notice   This function will calculate the investment return from the deposit information
     * @dev      We are simply multiplying the locked period days by the annual interest rate converted to daily
     * @param    _depositAmount the amount invested
     * @return    uint investment return value
     */
    function calculateReturn(
        uint256 _depositAmount,
        uint256 lockedPeriod,
        uint256 annualInterestRate
    ) public pure returns(uint256) {
        return lockedPeriod * convertAnnualReturnToDaily(_depositAmount,annualInterestRate) / 10000000;
    }

    /**
    * @notice   This function will convert an annual interest rate to a daily one
    * @dev      We are applying a mathematical calcule, dividing the deposit amount by the annual return and then divided this result by the number of days per year (365).
                Leap years have to be managed (some years has 366 days)
    * @param    _depositAmount the deposit amount
    * @return    uint the converted annual rate to daily
    */
    function convertAnnualReturnToDaily(
        uint256 _depositAmount,
        uint256 annualInterestRate
    ) public pure returns(uint256) {
        return ((annualInterestRate * (_depositAmount * 100)) * 1000) / 365; // multiplying by 1000 to avoit floating point
    }

        /**
     * @notice  This function will convert a string to a bytes
     * @dev     We return an hex bytes from a string using for each byte the fromHexChar() function to get the new value
     * @param   s the string to convert
     * @return  bytes the string converted to bytes
     */
    function fromStringToBytes(string memory s) public pure returns(bytes memory) {
        bytes memory ss = bytes(s);
        require(ss.length%2 == 0);
        bytes memory r = new bytes(ss.length/2);
        for (uint i=0; i<ss.length/2; ++i) {
            r[i] = bytes1(fromHexChar(uint8(ss[2*i])) * 16 +
                        fromHexChar(uint8(ss[2*i+1])));
        }
        return r;
    }

    /**
     * @notice  This function will a bytes to a bytes32
     * @dev     
     * @param   b the bytes to convert
     * @return  bytes32 the bytes converted to bytes32
     */
    function bytesToBytes32(bytes memory b) public pure returns(bytes32) {
        bytes32 out;
        for (uint i = 0; i < 32; i++) {
            out |= bytes32(b[0 + i] & 0xFF) >> (i * 8);
        }
        return out;
    }

        /**
     * @notice  This function will help to convert a string to an hex byte
     * @dev     We return value regarding of bytes1 values
     * @param   c bytes int value
     * @return  uint8 the new bytes int value
     */
    function fromHexChar(uint8 c) public pure returns (uint8) {
        if (bytes1(c) >= bytes1('0') && bytes1(c) <= bytes1('9')) {
            return c - uint8(bytes1('0'));
        }
        if (bytes1(c) >= bytes1('a') && bytes1(c) <= bytes1('f')) {
            return 10 + c - uint8(bytes1('a'));
        }
        if (bytes1(c) >= bytes1('A') && bytes1(c) <= bytes1('F')) {
            return 10 + c - uint8(bytes1('A'));
        }
        revert("fail");
    }
}