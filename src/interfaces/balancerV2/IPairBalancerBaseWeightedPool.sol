pragma solidity 0.8.18;

interface IPairBalancerBaseWeightedPool {
    function getNormalizedWeights() external view returns (uint256[] memory);

    function getSwapFeePercentage() external view returns (uint256);

    //                                pausedStatus, pauseWindowEndTime, bufferPeriodEndTime
    function getPausedState()
        external
        view
        returns (
            bool,
            uint256,
            uint256
        );

    function getLastInvariant() external view returns (uint256);
}
