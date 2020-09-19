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
    struct remStorage {
        address payable from;
        address payable to;
        uint amount;
        uint deadline;
    } 

    // Remittance balance mapping, maps a given puzzle to a second mapping
    // linking an address (the converter) to an amount (the remittance)
    mapping(bytes32 => remStorage) public balances;

    event logNewRemittance(address indexed sender, address indexed converter, uint amount, uint deadLine);
    event logFundsReleased(address indexed sender, uint amount, uint releasedAt);
    event logFundsReclaimed(address indexed sender, uint amount, uint reclaimedAt);

    constructor (bool _pauseState) Pausable(_pauseState) public {}

    /// Generates a remittance
    /// @param _recipient address of recipient
    /// @param _puzzleConverter puzzle provided by converter
    /// @param _puzzleRecipient puzzle provided by recipient
    /// @param _deadline deadline set for the remittance
    function createRemittance(
        address payable _recipient, 
        bytes32 _puzzleConverter, 
        bytes32 _puzzleRecipient,
        uint _deadline
    )
        external
        payable
        whenRunning
    {
        require(_deadline <= DEADLINE_LIMIT, 'Deadline cant be more than two hours into future');
        require(msg.value > 0, 'Cant create empty remittance');
        bytes32 puzzle = generatePuzzle(_puzzleConverter, _puzzleRecipient);
        require(balances[puzzle].from == address(0x0), 'Secret already in use');

        balances[puzzle].from = msg.sender;
        balances[puzzle].to = _recipient;
        balances[puzzle].amount = msg.value;
        balances[puzzle].deadline = block.timestamp + _deadline; 
        emit logNewRemittance(msg.sender, _recipient, msg.value, _deadline);
    }

    /// Generate a unique puzzle for this contract
    /// @param _puzzleConverter puzzle provided by converter
    /// @param _puzzleRecipient puzzle provided by recipient
    function generatePuzzle(bytes32 _puzzleConverter, bytes32 _puzzleRecipient)
        public
        view
        returns (bytes32 puzzle)
    {
        puzzle = keccak256(abi.encode(_puzzleConverter, _puzzleRecipient, address(this)));
    }
        
    /// Release the remittance
    /// @param _puzzleConverter puzzle provided by converter
    /// @param _puzzleRecipient puzzle provided by recipient
    /// @dev allows recipient to withdraw their alloted funds
	/// @return success true if succesfull
    function releaseFunds(bytes32 _puzzleConverter, bytes32 _puzzleRecipient) 
        public
        whenRunning
        returns (bool success)
    {
        bytes32 puzzle = generatePuzzle(_puzzleConverter, _puzzleRecipient);
        (uint amount, uint deadline, , address payable recipient) = retrieveRemInfo(puzzle);
        require(msg.sender == recipient, 'Only recipient can release funds');
        require(block.timestamp <= deadline, 'Remittance has lapsed');

        balances[puzzle].amount = 0;
        emit logFundsReleased(msg.sender, amount, block.timestamp);

        (success, ) = msg.sender.call{value: amount}("");
        require(success, 'Transfer failed!');
        return true;
    } 

    /// Reclaim funds from expired remittance
    /// @param _puzzleConverter puzzle provided by converter
    /// @param _puzzleRecipient puzzle provided by recipient
    /// @dev allows sender to withdraw their sent funds
	/// @return success true if succesfull
    function reclaimFunds(bytes32 _puzzleConverter, bytes32 _puzzleRecipient)
        public
        returns (bool success)
    {
        bytes32 puzzle = generatePuzzle(_puzzleConverter, _puzzleRecipient);
        (uint amount, uint deadline, address payable sender, ) = retrieveRemInfo(puzzle);
        require(msg.sender == sender, 'Only sender can reclaim funds');
        require(block.timestamp > deadline, 'Remittance needs to expire');

        balances[puzzle].amount = 0;
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
        amount = balances[puzzle].amount;
        require(amount > 0, 'Invalid remittance');
        from = balances[puzzle].from;
        to = balances[puzzle].to;
        deadline = balances[puzzle].deadline;

        return (amount, deadline, from, to);
    }
}
