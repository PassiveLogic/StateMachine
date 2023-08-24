//
//  Created by Christopher Fuller on 12/21/19.
//  Copyright © 2019 Tinder. All rights reserved.
//

import Nimble
@testable import StateMachine
import XCTest

final class StateMachine_Turnstile_Tests: XCTestCase, StateMachineBuilder {

    enum Constant {

        static let farePrice: Int = 50
    }

    indirect enum State: Equatable {

        case locked(credit: Int), unlocked, broken(oldState: State)
    }

    enum Event: Equatable {

        case insertCoin(Int), admitPerson, machineDidFail, machineRepairDidComplete
    }

    enum SideEffect {

        case soundAlarm, closeDoors, openDoors, orderRepair
    }

    typealias TurnstileStateMachine = StateMachine<State, Event, SideEffect>
    typealias ValidTransition = TurnstileStateMachine.Transition.Valid

    static func turnstileStateMachine(withInitialState _state: State, logger: Logger) -> TurnstileStateMachine {
        TurnstileStateMachine {
            initialState(_state)
            state(.locked) {
                on(.insertCoin) { locked, insertCoin in
                    let newCredit: Int = try locked.credit() + insertCoin.value()
                    if newCredit >= Constant.farePrice {
                        return transition(to: .unlocked, emit: .openDoors)
                    } else {
                        return transition(to: .locked(credit: newCredit))
                    }
                }
                on(.admitPerson) {
                    dontTransition(emit: .soundAlarm)
                }
                on(.machineDidFail) {
                    transition(to: .broken(oldState: $0), emit: .orderRepair)
                }
            }
            state(.unlocked) {
                on(.admitPerson) {
                    transition(to: .locked(credit: 0), emit: .closeDoors)
                }
            }
            state(.broken) {
                on(.machineRepairDidComplete) { broken in
                    transition(to: try broken.oldState())
                }
            }
        }
    }

    var logger: Logger!

    override func setUp() {
        super.setUp()
        logger = .init()
    }

    override func tearDown() {
        logger = nil
        super.tearDown()
    }

    func givenState(is state: State) -> TurnstileStateMachine {
        let stateMachine: TurnstileStateMachine = Self.turnstileStateMachine(withInitialState: state, logger: logger)
        expect(stateMachine.state).to(equal(state))
        return stateMachine
    }

    func test_givenStateIsLocked_whenInsertCoin_andCreditLessThanFarePrice_shouldTransitionToLockedState() async throws {

        // Given
        let stateMachine = givenState(is: .locked(credit: 0))

        // When
        let transition = try await stateMachine.transition(.insertCoin(10))

        // Then
        expect(stateMachine.state).to(equal(.locked(credit: 10)))
        expect(transition).to(equal(ValidTransition(fromState: .locked(credit: 0),
                                                    event: .insertCoin(10),
                                                    toState: .locked(credit: 10),
                                                    sideEffect: nil)))
    }

    func test_givenStateIsLocked_whenInsertCoin_andCreditEqualsFarePrice_shouldTransitionToUnlockedStateAndOpenDoors() async throws {

        // Given
        let stateMachine = givenState(is: .locked(credit: 35))

        // When
        let transition = try await stateMachine.transition(.insertCoin(15))

        // Then
        expect(stateMachine.state).to(equal(.unlocked))
        expect(transition).to(equal(ValidTransition(fromState: .locked(credit: 35),
                                                    event: .insertCoin(15),
                                                    toState: .unlocked,
                                                    sideEffect: .openDoors)))
    }

    func test_givenStateIsLocked_whenInsertCoin_andCreditMoreThanFarePrice_shouldTransitionToUnlockedStateAndOpenDoors() async throws {

        // Given
        let stateMachine = givenState(is: .locked(credit: 35))

        // When
        let transition = try await stateMachine.transition(.insertCoin(20))

        // Then
        expect(stateMachine.state).to(equal(.unlocked))
        expect(transition).to(equal(ValidTransition(fromState: .locked(credit: 35),
                                                    event: .insertCoin(20),
                                                    toState: .unlocked,
                                                    sideEffect: .openDoors)))
    }

    func test_givenStateIsLocked_whenAdmitPerson_shouldTransitionToLockedStateAndSoundAlarm() async throws {

        // Given
        let stateMachine = givenState(is: .locked(credit: 35))

        // When
        let transition = try await stateMachine.transition(.admitPerson)

        // Then
        expect(stateMachine.state).to(equal(.locked(credit: 35)))
        expect(transition).to(equal(ValidTransition(fromState: .locked(credit: 35),
                                                    event: .admitPerson,
                                                    toState: .locked(credit: 35),
                                                    sideEffect: .soundAlarm)))
    }

    func test_givenStateIsLocked_whenMachineDidFail_shouldTransitionToBrokenStateAndOrderRepair() async throws {

        // Given
        let stateMachine = givenState(is: .locked(credit: 15))

        // When
        let transition = try await stateMachine.transition(.machineDidFail)

        // Then
        expect(stateMachine.state).to(equal(.broken(oldState: .locked(credit: 15))))
        expect(transition).to(equal(ValidTransition(fromState: .locked(credit: 15),
                                                    event: .machineDidFail,
                                                    toState: .broken(oldState: .locked(credit: 15)),
                                                    sideEffect: .orderRepair)))
    }

    func test_givenStateIsUnlocked_whenAdmitPerson_shouldTransitionToLockedStateAndCloseDoors() async throws {

        // Given
        let stateMachine = givenState(is: .unlocked)

        // When
        let transition = try await stateMachine.transition(.admitPerson)

        // Then
        expect(stateMachine.state).to(equal(.locked(credit: 0)))
        expect(transition).to(equal(ValidTransition(fromState: .unlocked,
                                                    event: .admitPerson,
                                                    toState: .locked(credit: 0),
                                                    sideEffect: .closeDoors)))
    }

    func test_givenStateIsBroken_whenMachineRepairDidComplete_shouldTransitionToLockedState() async throws {

        // Given
        let stateMachine = givenState(is: .broken(oldState: .locked(credit: 15)))

        // When
        let transition = try await stateMachine.transition(.machineRepairDidComplete)

        // Then
        expect(stateMachine.state).to(equal(.locked(credit: 15)))
        expect(transition).to(equal(ValidTransition(fromState: .broken(oldState: .locked(credit: 15)),
                                                    event: .machineRepairDidComplete,
                                                    toState: .locked(credit: 15),
                                                    sideEffect: nil)))
    }
}

extension StateMachine_Turnstile_Tests.State: StateMachineHashable {

    enum HashableIdentifier {

        case locked, unlocked, broken
    }

    var hashableIdentifier: HashableIdentifier {
        switch self {
        case .locked:
            return .locked
        case .unlocked:
            return .unlocked
        case .broken:
            return .broken
        }
    }

    var associatedValue: Any {
        switch self {
        case let .locked(credit):
            return credit
        case .unlocked:
            return ()
        case let .broken(oldState):
            return oldState
        }
    }
}

extension StateMachine_Turnstile_Tests.Event: StateMachineHashable {

    enum HashableIdentifier {

        case insertCoin, admitPerson, machineDidFail, machineRepairDidComplete
    }

    var hashableIdentifier: HashableIdentifier {
        switch self {
        case .insertCoin:
            return .insertCoin
        case .admitPerson:
            return .admitPerson
        case .machineDidFail:
            return .machineDidFail
        case .machineRepairDidComplete:
            return .machineRepairDidComplete
        }
    }

    var associatedValue: Any {
        switch self {
        case let .insertCoin(value):
            return value
        case .admitPerson:
            return ()
        case .machineDidFail:
            return ()
        case .machineRepairDidComplete:
            return ()
        }
    }
}
