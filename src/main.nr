
use std::cmp::Ordering;
use std::hash::sha256;

// PLAN:
// - check dummy signatures for all participants
// - sort the array of participants
//   + sorting function
//   + constrained verify
//   + unconstrained calculation
// - get the top three participants


////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Game definition
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Example address type
type Address = [u8; 32];

// This is just a sha256 hash
type DummySignature = [u8; 32];

// Dummy pub key
struct DummyPubKey {}

impl DummyPubKey {
    // Just hash the message, ignoring the DummyPubKey
    fn sign<let N: u32>(self, message: [u8; N]) -> DummySignature {
        sha256(message)
    }

    // Check that the hash of the message matches the "signature"
    fn assert_verify<let N: u32>(self, message: [u8; N], signature: DummySignature) {
        assert(sha256(message) == signature);
    }
}

/// A participant consists of an Address, their score, and a signature to ensure
/// that each participant is valid
///
/// Incoming :)
/// #[derive(Serialize)]
struct Participant {
    address: Address,
    score: u8,
    signature: DummySignature,
}

impl Participant {
    // Serialize a pariticpant into a fixed-length array of u8's
    fn serialize(self) -> [u8; 33] {
        let mut result = [0; 33];
        for index in 0..32 {
            result[index] = self.address[index];
        }
        result[32] = self.score;
        result
    }

    // Assert that the participant's signature is valid
    fn assert_signature_valid(self, signer: DummyPubKey) {
        signer.assert_verify(self.serialize(), self.signature);
    }
}

impl Ord for Participant {
    fn cmp(self, other: Participant) -> Ordering {
        self.score.cmp(other.score)
    }
}

struct Winners {
    first_place: Address,
    second_place: Address,
    third_place: Address,
}

impl Winners {
    // Calculate the top three winners!
    fn new<let N: u32>(participants: [Participant; N], signer: DummyPubKey) -> Self {
        // We need at least three participants
        assert(N >= 3);

        // Check the (dummy) signatures
        assert_signatures_valid(participants, signer);

        // Find first, second, third place participant addresses
        let sorted_participants = sort_array_gts(participants);
        let first_place = sorted_participants[0].address;
        let second_place = sorted_participants[1].address;
        let third_place = sorted_participants[2].address;

        Self {
            first_place,
            second_place,
            third_place,
        }
    }
}

// Assert that all of the signatures are valid
fn assert_signatures_valid<let N: u32>(participants: [Participant; N], signer: DummyPubKey) {
    for participant in participants {
        participant.assert_signature_valid(signer)
    }
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Sorting in O(N) circuit-time
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Sorting an array greatest-to-smallest in O(N) circuit time
fn sort_array_gts<T, let N: u32>(input: [T; N]) -> [T; N] where T: Ord {
    let mut result = input;

    // The unsafe block (unconstrained function) is run _outside_ the circuit!
    unsafe {
        result = unconstrained_sort_array_gts(input);
    }

    // We need to constrain the output _inside_ the circuit,
    // which can be done in O(N) time!
    assert_array_sorted_gts(result);

    result
}

unconstrained fn unconstrained_sort_array_gts<T, let N: u32>(input: [T; N]) -> [T; N] where T: Ord {
    let mut scratch = input.map(|x| Option::some(x));
    let mut result = input;
    for index in 0..N {
        result[index] = find_and_remove_largest(&mut scratch);
    }
    result
}

/// Find the largest `Some(_)` value, replace it with `None`, and return it
///
/// (panics on empty input)
unconstrained fn find_and_remove_largest<T, let N: u32>(input: &mut [Option<T>; N]) -> T where T: Ord {
    let mut largest = input[0];
    let mut index_of_largest = 0;
    for index in 1..N {
        let current_value = input[index];

        // Noir currently lacks enums, so we need to do if/then checks
        if current_value.is_some() {
            if largest.is_none() {
                largest = current_value;
                index_of_largest = index;
            } else if largest.unwrap() < current_value.unwrap() {
                largest = current_value;
                index_of_largest = index;
            }
        }
    }

    // remove largest from input
    input[index_of_largest] = Option::none();

    // unwrap the largest value or panic if it's Option::none
    largest.unwrap()
}

// Check that each value is greater than or equal to the next value
fn assert_array_sorted_gts<T, let N: u32>(input: [T; N]) where T: Ord {
    for index in 0..N-1 {
        assert(input[index] >= input[index+1]);
    }
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Demo
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// For simplicity, we generate inputs in main(),
// but if we had real inputs, we'd use the following signature for main():
//
// fn main(participants: [Participant; 100], signer: DummyPubKey) -> pub Winners {

// Generate participants and calculate Winners
fn main() -> pub Winners {
    // Dummy signer
    let signer = DummyPubKey {};

    // Dummy participants
    let mut participants: [Participant; 100] = [std::mem::zeroed(); 100];
    for index in 0..100 {
        // The example address is [index, 0, .., 0]
        let mut address: [u8; 32] = std::mem::zeroed();
        address[0] = 1 + index as u8;

        let mut participant = Participant {
            address,
            score: index as u8,
            // We leave an empty signature to calculate with signer.sign(..)
            signature: std::mem::zeroed(),
        };

        // Then we "sign" each participant
        let partitipant_dummy_signature = signer.sign(participant.serialize());
        participant.signature = partitipant_dummy_signature;
        participants[index] = participant;
    }

    // Check that the participants array isn't already sorted
    assert(participants.cmp(sort_array_gts(participants)) != Ordering::equal());

    // Calculate winners
    let winners = Winners::new(participants, signer);

    // Clear screen
    for _ in 0..256 {
        println("");
    }

    // Print 1st, 2nd, 3rd place for debugging
    println("first_place (expect 100th participant)");
    println(winners.first_place);
    println("");

    println("second_place (expect 99th participant)");
    println(winners.second_place);
    println("");

    println("third_place (expect 98th participant)");
    println(winners.third_place);
    println("");

    // Return winners at the end
    winners
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Tests
////////////////////////////////////////////////////////////////////////////////////////////////////////////

#[test]
unconstrained fn test_find_and_remove_largest() {
    let mut test_input: [Option<u8>; 4] = [1,2,3,4].map(|x| Option::some(x));
    let result = find_and_remove_largest(&mut test_input);

    assert(test_input == [Option::some(1), Option::some(2), Option::some(3), Option::none()]);
    assert(result == 4);
}

#[test]
unconstrained fn test_find_and_remove_largest_reversed_input() {
    let mut test_input: [Option<u8>; 4] = [4,3,2,1].map(|x| Option::some(x));
    let result = find_and_remove_largest(&mut test_input);

    assert(test_input == [Option::none(), Option::some(3), Option::some(2), Option::some(1)]);
    assert(result == 4);
}

#[test]
fn test_sort_array_gts() {
    let test_input: [u8; 4] = [4, 1, 2, 3];
    let result = sort_array_gts(test_input);

    println(result);
    assert(result == [4, 3, 2, 1]);
}

#[test]
fn test_sort_array_gts_reversed_input() {
    let test_input: [u8; 4] = [3, 2, 1, 4];
    let result = sort_array_gts(test_input);

    println(result);
    assert(result == [4, 3, 2, 1]);
}

