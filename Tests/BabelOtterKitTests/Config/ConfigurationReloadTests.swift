import Testing

@testable import BabelOtterKit

@Suite("A reload keeps what works")
struct ConfigurationReloadTests {

    private let problem = ConfigurationProblem(
        file: "config.json", field: "retentionDays", detail: "expected Int, found something else")

    private var previous: Configuration {
        var configuration = Configuration.default
        configuration.retentionDays = 30
        return configuration
    }

    private var edited: Configuration {
        var configuration = Configuration.default
        configuration.retentionDays = 7
        return configuration
    }

    @Test("a clean file replaces the configuration in use")
    func cleanReplaces() {
        let result = ConfigurationReload.apply(
            previous: previous, loaded: LoadedConfiguration(configuration: edited, problems: []),
            fileExists: true, isLaunch: false)
        #expect(result.configuration == edited)
        #expect(result.problems.isEmpty)
    }

    @Test("at launch a broken file gives the defaults and its problems, as before")
    func brokenAtLaunch() {
        let result = ConfigurationReload.apply(
            previous: .default, loaded: LoadedConfiguration(configuration: .default, problems: [problem]),
            fileExists: true, isLaunch: true)
        #expect(result.configuration == .default)
        #expect(result.problems == [problem])
    }

    @Test("on reload a broken file keeps the configuration in use and says so")
    func brokenOnReload() {
        let result = ConfigurationReload.apply(
            previous: previous, loaded: LoadedConfiguration(configuration: .default, problems: [problem]),
            fileExists: true, isLaunch: false)
        #expect(result.configuration == previous)
        #expect(result.problems == [ConfigurationProblem(
            file: "config.json", field: "retentionDays",
            detail: "expected Int, found something else - still using the previous settings")])
    }

    @Test("a fixed file clears the problems a launch reported")
    func fixedFileClearsProblems() {
        let launch = ConfigurationReload.apply(
            previous: .default, loaded: LoadedConfiguration(configuration: .default, problems: [problem]),
            fileExists: true, isLaunch: true)
        let fixed = ConfigurationReload.apply(
            previous: launch.configuration, loaded: LoadedConfiguration(configuration: edited, problems: []),
            fileExists: true, isLaunch: false)
        #expect(fixed.configuration == edited)
        #expect(fixed.problems.isEmpty)
    }

    @Test("a file deleted while running keeps the configuration in use")
    func missingOnReload() {
        let result = ConfigurationReload.apply(
            previous: previous, loaded: LoadedConfiguration(configuration: .default, problems: []),
            fileExists: false, isLaunch: false)
        #expect(result.configuration == previous)
        #expect(result.problems == [ConfigurationProblem(
            file: "config.json", field: nil,
            detail: "the file is missing - still using the previous settings")])
    }

    @Test("no file at launch is a first launch, not a problem")
    func missingAtLaunch() {
        let result = ConfigurationReload.apply(
            previous: .default, loaded: LoadedConfiguration(configuration: .default, problems: []),
            fileExists: false, isLaunch: true)
        #expect(result.configuration == .default)
        #expect(result.problems.isEmpty)
    }

    @Test("a summary names the field when there is one")
    func summary() {
        #expect(problem.summary == "retentionDays: expected Int, found something else")
        #expect(ConfigurationProblem(file: "config.json", field: nil, detail: "not JSON").summary
            == "not JSON")
    }
}
