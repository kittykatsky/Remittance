pragma solidity ^0.6.0;

import "./Ownable.sol";

/// @author Kat
/// @title A contract for splitting ethereum 
contract Remittance is Ownable {
    address payable public converter;
    address payable public recipient;

    mapping(bytes32 => mapping(address => uint)) public balance;

    enum State {Created, Released}

    State public state;

    event logFundsReleased(address indexed sender, uint amount);

    constructor (
        address payable _converter, 
        address payable _recipient, 
        bytes32 puzzleConverter, 
        bytes32 puzzleRecipient
    )
        public
        payable
    {
        converter = _converter;
        recipient = _recipient;
        bytes32 puzzle = generatePuzzle(puzzleConverter, puzzleRecipient);
        balance[puzzle][converter] = msg.value; 
        state = State.Created;
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
        returns (bool)
    {
        require(msg.sender == converter, 'only converter can release funds');
        require(state == State.Created, 'Remittance not available');

        uint amount = balance[generatePuzzle(_puzzleConverter, _puzzleRecipient)][msg.sender];
        require(amount > 0, 'No funds available');

        state = State.Released;
        emit logFundsReleased(msg.sender, amount);
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, 'Transfer failed!');
        return true;
    } 

}
