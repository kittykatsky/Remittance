pragma solidity ^0.6.0;

import "./Pausable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

/// @author Kat
/// @title A contract for transfering ethereum through an intermediary 
contract Remittance is Pausable {

    using SafeMath for uint;

    address payable public converter;
    uint public remittanceDeadLine; 

    mapping(bytes32 => mapping(address => uint)) public balance;

    enum State {Created, Released}

    State public state;

    event logNewRemittance(address indexed sender, address indexed converter, uint amount, uint deadLine);
    event logFundsReleased(address indexed sender, uint amount, uint releasedAt);


    //constructor(bool pauseState) Pausable(pauseState) public {}
    constructor (
        address payable _converter, 
        bytes32 puzzleConverter, 
        bytes32 puzzleRecipient,
        uint _deadline,
        bool pauseState
    )
    Pausable(pauseState)
        public
        payable
    {
        require(_deadline <= 7200, 'Deadline cant be more than two hours into future');
        converter = _converter;
        bytes32 puzzle = generatePuzzle(puzzleConverter, puzzleRecipient);
        balance[puzzle][converter] = msg.value; 
        remittanceDeadLine = block.timestamp + _deadline;
        state = State.Created;
        emit logNewRemittance(msg.sender, converter, msg.value, remittanceDeadLine);
    }
    
    /// @dev Generates the puzzle for the remitance 
    function generatePuzzle(bytes32 _puzzleConverter, bytes32 _puzzleRecipient)
        public
        view
        returns (bytes32 puzzle)
    {
        puzzle = keccak256(abi.encodePacked(uint(_puzzleConverter), uint(_puzzleRecipient)));
    }
        
    /// Release the remittance
    /// @param _puzzleConverter puzzle
    /// @param _puzzleRecipient puzzle
    /// @dev allows payee to withdraw their alloted funds
	/// @return true if succesfull
    function releaseFunds(bytes32 _puzzleConverter, bytes32 _puzzleRecipient) 
        external 
        whenRunning
        returns (bool)
    {
        require(block.timestamp <= remittanceDeadLine, 'Remittance has lapsed');
        require(msg.sender == converter, 'only converter can release funds');
        require(state == State.Created, 'Remittance not available');

        uint amount = balance[generatePuzzle(_puzzleConverter, _puzzleRecipient)][msg.sender];
        require(amount > 0, 'No funds available');

        state = State.Released;
        emit logFundsReleased(msg.sender, amount, block.timestamp);
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, 'Transfer failed!');
        return true;
    } 

}
