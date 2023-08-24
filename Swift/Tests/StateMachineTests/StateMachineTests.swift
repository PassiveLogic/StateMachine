//
//  Created by Christopher Fuller on 12/21/19.
//  Copyright © 2019 Tinder. All rights reserved.
//

import Nimble
@testable import StateMachine
import XCTest

final class StateMachineTests: XCTestCase, StateMachineBuilder {

    enum State: StateMachineHashable {

        case stateOne, stateTwo
    }

    enum Event: StateMachineHashable {

        case eventOne, eventTwo
    }

    enum SideEffect {

        case commandOne, commandTwo, commandThree
    }

    typealias TestStateMachine = StateMachine<State, Event, SideEffect>
    typealias ValidTransition = TestStateMachine.Transition.Valid
    typealias InvalidTransition = TestStateMachine.Transition.Invalid

    static func testStateMachine(withInitialState _state: State) -> TestStateMachine {
        TestStateMachine {
            initialState(_state)
            state(.stateOne) {
                on(.eventOne) {
                    dontTransition(emit: .commandOne)
                }
                on(.eventTwo) {
                    transition(to: .stateTwo, emit: .commandTwo)
                }
            }
            state(.stateTwo) {
                on(.eventTwo) {
                    dontTransition(emit: .commandThree)
                }
            }
        }
    }

    func givenState(is state: State) -> TestStateMachine {
        let stateMachine: TestStateMachine = Self.testStateMachine(withInitialState: state)
        expect(stateMachine.state).to(equal(state))
        return stateMachine
    }

    func testDontTransition() async throws {

        // Given
        let stateMachine: TestStateMachine = givenState(is: .stateOne)

        // When
        let transition: ValidTransition = try await stateMachine.transition(.eventOne)

        // Then
        expect(stateMachine.state).to(equal(.stateOne))
        expect(transition).to(equal(ValidTransition(fromState: .stateOne,
                                                    event: .eventOne,
                                                    toState: .stateOne,
                                                    sideEffect: .commandOne)))
    }

    func testTransition() async throws {

        // Given
        let stateMachine: TestStateMachine = givenState(is: .stateOne)

        // When
        let transition: ValidTransition = try await stateMachine.transition(.eventTwo)

        // Then
        expect(stateMachine.state).to(equal(.stateTwo))
        expect(transition).to(equal(ValidTransition(fromState: .stateOne,
                                                    event: .eventTwo,
                                                    toState: .stateTwo,
                                                    sideEffect: .commandTwo)))
    }

    func testInvalidTransition() async throws {

        // Given
        let stateMachine: TestStateMachine = givenState(is: .stateTwo)

        // When
        let transition: () async throws -> ValidTransition = {
            try await stateMachine.transition(.eventOne)
        }

        // Then
        await expect(transition).to(throwError { error in
            expect(error).to(beAKindOf(InvalidTransition.self))
        })
    }

    func testObservation() async throws {

        var results: [Result<ValidTransition, InvalidTransition>] = []

        // Given
        let stateMachine: TestStateMachine = givenState(is: .stateOne)
            .startObserving(self) {
                results.append($0.mapError { $0 as! InvalidTransition })
            }

        // When
        try await stateMachine.transition(.eventOne)
        try await stateMachine.transition(.eventTwo)
        let transition: () async throws -> ValidTransition = {
            try await stateMachine.transition(.eventOne)
        }

        // Then
        await expect(transition).to(throwError { error in
            expect(error).to(beAKindOf(InvalidTransition.self))
        })

        // When
        try await stateMachine.transition(.eventTwo)

        // Then
        expect(results).to(equal([
            .success(ValidTransition(fromState: .stateOne,
                                     event: .eventOne,
                                     toState: .stateOne,
                                     sideEffect: .commandOne)),
            .success(ValidTransition(fromState: .stateOne,
                                     event: .eventTwo,
                                     toState: .stateTwo,
                                     sideEffect: .commandTwo)),
            .failure(InvalidTransition()),
            .success(ValidTransition(fromState: .stateTwo,
                                     event: .eventTwo,
                                     toState: .stateTwo,
                                     sideEffect: .commandThree))
        ]))
    }

    func testStopObservation() async throws {

        var transitionCount: Int = 0

        // Given
        let stateMachine: TestStateMachine = givenState(is: .stateOne)
            .startObserving(self) { _ in
                transitionCount += 1
            }

        // When
        try await stateMachine.transition(.eventOne)
        try await stateMachine.transition(.eventOne)

        // Then
        expect(transitionCount).to(equal(2))

        // When
        stateMachine.stopObserving(self)
        try await stateMachine.transition(.eventOne)
        try await stateMachine.transition(.eventOne)

        // Then
        expect(transitionCount).to(equal(2))
    }

    func testRecursionDetectedError() async throws {

        var error: TestStateMachine.StateMachineError? = nil

        // Given
        let stateMachine: TestStateMachine = givenState(is: .stateOne)

        stateMachine.startObserving(self) { [unowned stateMachine] _ in
            do {
                try await stateMachine.transition(.eventOne)
            } catch let e as TestStateMachine.StateMachineError {
                error = e
            } catch {}
        }

        // When
        try await stateMachine.transition(.eventOne)

        // Then
        expect(error).to(equal(.recursionDetected))
    }
}

final class Logger {

    private(set) var messages: [String] = []

    func log(_ message: String) {
        messages.append(message)
    }
}

func log(_ expectedMessages: String...) -> Predicate<Logger> {
    let expectedString: String = stringify(expectedMessages.joined(separator: "\\n"))
    return Predicate {
        let actualMessages: [String]? = try $0.evaluate()?.messages
        let actualString: String = stringify(actualMessages?.joined(separator: "\\n"))
        let message: ExpectationMessage = .expectedCustomValueTo("log <\(expectedString)>",
                                                                 actual: "<\(actualString)>")
        return PredicateResult(bool: actualMessages == expectedMessages, message: message)
    }
}
