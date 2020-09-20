pragma solidity ^0.6.0;

import "./Pausable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

/// @author Kat
/// @title A contract for transfering ethereum through an intermediary 
contract Remittance is Pausable {

    using SafeMath for uint;

    // Remittance deadlince cant be more than 2 hours into the future
    uint16 constant DEADLINE_LIMIT = 7200;

    // Struct to hold information about individual remittances
    struct remittanceStruct {
        address payable from;
        address payable to;
        uint amount;
        uint deadline;
    } 

    // Remittance balance mapping, maps a given puzzle to a second mapping
    // linking an address (the converter) to an amount (the remittance)
    mapping(bytes32 => remittanceStruct) public remittances;

    event logNewRemittance(address indexed sender, address indexed converter, uint amount, uint deadLine);
    event logFundsReleased(address indexed sender, uint amount, uint releasedAt);
    event logFundsReclaimed(address indexed sender, uint amount, uint reclaimedAt);

    constructor (bool _pauseState) Pausable(_pauseState) public {}

    /// Generates a remittance
    /// @param converter address of converter 
    /// @param puzzle puzzle provided to unlock remittance
    /// @param deadline deadline set for the remittance
    function createRemittance(
        address payable converter, 
        bytes32 puzzle, 
        uint deadline
    )
        external
        payable
        whenRunning
    {
        require(deadline <= DEADLINE_LIMIT, 'Deadline cant be more than two hours into future');
        require(msg.value > 0, 'Cant create empty remittance');
        require(remittances[puzzle].from == address(0x0), 'Secret already in use');

        remittances[puzzle].from = msg.sender;
        remittances[puzzle].to = converter;
        remittances[puzzle].amount = msg.value;
        remittances[puzzle].deadline = block.timestamp + deadline; 
        emit logNewRemittance(msg.sender, converter, msg.value, deadline);
    }

    /// Generate a unique puzzle for this contract
    /// @param converterAddress address of converter
    /// @param puzzlePiece puzzle piece provided by recipient
    /// @dev puzzle combines the address of the converter, 
    /// the contract and the puzzle piece provided by the reciever
	/// @return puzzle a hash generated from the input paramaters
    function generatePuzzle(address converterAddress, bytes32 puzzlePiece)
        public
        view
        returns (bytes32 puzzle)
    {
        puzzle = keccak256(abi.encode(converterAddress, puzzlePiece, address(this)));
    }
        
    /// Release the remittance
    /// @param puzzle used to unlock remittance
    /// @dev allows converter to withdraw the alloted funds
	/// @return success true if succesfull
    function releaseFunds(bytes32 puzzle) 
        public
        whenRunning
        returns (bool success)
    {
        (uint amount, uint deadline, , address payable to) = retrieveRemInfo(puzzle);
        require(msg.sender == to, 'Only converter can release funds');
        require(block.timestamp < deadline, 'Remittance has lapsed');

        remittances[puzzle].amount = 0;
        emit logFundsReleased(msg.sender, amount, block.timestamp);

        (success, ) = msg.sender.call{value: amount}("");
        require(success, 'Transfer failed!');
        return true;
    } 

    /// Reclaim funds from expired remittance
    /// @param puzzle used to unlock remittance
    /// @dev allows sender to withdraw their sent funds
	/// @return success true if succesfull
    function reclaimFunds(bytes32 puzzle)
        public
        returns (bool success)
    {
        (uint amount, uint deadline, address payable from, ) = retrieveRemInfo(puzzle);
        require(msg.sender == from, 'Only sender can reclaim funds');
        require(block.timestamp >= deadline, 'Remittance needs to expire');

        remittances[puzzle].amount = 0;
        emit logFundsReclaimed(msg.sender, amount, block.timestamp);

        (success, ) = msg.sender.call{value: amount}("");
        require(success, 'Transfer failed!');
        return true;
    }

    /// Return Remittance struct data
    /// @param puzzle puzzle associated with remittance struct
    /// @dev repeated code moved from release/reclaim funds to its own function
	/// @return amount amount of ether in remittance
	/// @return deadline remittance deadline
	/// @return from remittance created
	/// @return to remittance reciever
    function retrieveRemInfo(bytes32 puzzle) 
        private 
        returns(uint amount, uint deadline, address payable from, address payable to)
    {
        amount = remittances[puzzle].amount;
        require(amount > 0, 'Invalid remittance');
        from = remittances[puzzle].from;
        to = remittances[puzzle].to;
        deadline = remittances[puzzle].deadline;

        return (amount, deadline, from, to);
    }
}
