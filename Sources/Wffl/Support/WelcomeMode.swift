import Foundation

/// What a person sees in this campaign. Decided once, from the install's history, and stored: a new
/// install that quits mid-setup must not be treated as a returning one the next time.
enum WelcomeMode: String {
    /// Opening film, feature tour, setup, then the falling cubes.
    case film
    /// A fresh install: setup alone, then the falling cubes.
    case setupOnly
}
