pragma solidity ^0.6.0;

import "./Pausable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

/// @author Kat
/// @title A contract for transfering ethereum through an intermediary 
contract Remittance is Pausable {

    using SafeMath for uint;

    address payable public converter;
    uint public remittanceDeadLine; 
    uint16 constant deadLineLimit = 7200;

    // remittance balance mapping, maps a given puzzle to a second mapping
    // linking an address (the converter) to an amount (the remittance)
    mapping(bytes32 => mapping(address => uint)) public balances;


    event logNewRemittance(address indexed sender, address indexed converter, uint amount, uint deadLine);
    event logFundsReleased(address indexed sender, uint amount, uint releasedAt);


    constructor (bool pauseState) Pausable(pauseState) public {}

    /// Generates a remittance
    /// @param _converter converter address
    /// @param _puzzleConverter puzzle provided by converter
    /// @param _puzzleRecipient puzzle provided by recipient
    /// @param _deadline deadline set for the remittance
    function createRemittance(
        address payable _converter, 
        bytes32 _puzzleConverter, 
        bytes32 _puzzleRecipient,
        uint _deadline
    )
        public
        payable
        whenRunning
    {
        require(_deadline <= deadLineLimit, 'Deadline cant be more than two hours into future');
        converter = _converter;
        bytes32 puzzle = generatePuzzle(_puzzleConverter, _puzzleRecipient);
        balances[puzzle][converter] = msg.value; 
        remittanceDeadLine = block.timestamp + _deadline;
        emit logNewRemittance(msg.sender, converter, msg.value, remittanceDeadLine);
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
    /// @dev allows payee to withdraw their alloted funds
	/// @return true if succesfull
    function releaseFunds(bytes32 _puzzleConverter, bytes32 _puzzleRecipient) 
        external 
        whenRunning
        returns (bool)
    {
        require(block.timestamp <= remittanceDeadLine, 'Remittance has lapsed');
        require(msg.sender == converter, 'only converter can release funds');

        uint amount = balances[generatePuzzle(_puzzleConverter, _puzzleRecipient)][msg.sender];
        require(amount > 0, 'No funds available');

        emit logFundsReleased(msg.sender, amount, block.timestamp);
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, 'Transfer failed!');
        return true;
    } 

    function reclaimFunds(bytes32 _puzzleConverter, bytes32 _puzzleRecipient)
        public
        returns (bool success)
    {
        require(msg.sender == getOwner(), 'only Owner can reclaim');
        require(remittanceDeadLine < block.timestamp, 'Remittance not expired');
        uint amount = balances[generatePuzzle(_puzzleConverter, _puzzleRecipient)][converter];
        require(amount > 0, 'No ether in remittance');

        (success, ) = msg.sender.call{value: amount}("");
        require(success, 'Transfer failed!');
        return true;
    }
}
