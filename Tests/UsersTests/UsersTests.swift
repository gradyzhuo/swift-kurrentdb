//
//  UsersTests.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2026/2/16.
//

import Foundation
@testable import KurrentDB
import Testing

@Suite("Users Tests", .serialized)
struct UsersTests: Sendable {
    let settings: ClientSettings

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .cerificate(source: .crtInBundle("ca", inBundle: .module)!)
    }

    // MARK: - Create User

    @Test("It should create a new user and return user details.")
    func testCreateUser() async throws {
        let client = KurrentDBClient(settings: settings)
        let loginName = "test-user-\(UUID().uuidString.prefix(8))"

        let userDetails = try await client.users.create(
            loginName: loginName,
            password: "Password123!",
            fullName: "Test User",
            groups: [.ops]
        )

        let details = try #require(userDetails)
        #expect(details.loginName == loginName)
        #expect(details.fullName == "Test User")
        #expect(details.groups.contains(.ops))
        #expect(!details.disabled)

        // Cleanup
        try await client.user(loginName).disable()
    }

    @Test("It should create a user with variadic groups.")
    func testCreateUserVariadicGroups() async throws {
        let client = KurrentDBClient(settings: settings)
        let loginName = "test-user-\(UUID().uuidString.prefix(8))"

        let userDetails = try await client.users.create(
            loginName: loginName,
            password: "Password123!",
            fullName: "Test User Variadic",
            groups: .ops, .admins
        )

        let details = try #require(userDetails)
        #expect(details.groups.contains(.ops))
        #expect(details.groups.contains(.admins))

        // Cleanup
        try await client.user(loginName).disable()
    }

    // MARK: - Get User Details

    @Test("It should retrieve details for an existing user.")
    func testGetUserDetails() async throws {
        let client = KurrentDBClient(settings: settings)
        let loginName = "test-user-\(UUID().uuidString.prefix(8))"

        _ = try await client.users.create(
            loginName: loginName,
            password: "Password123!",
            fullName: "Details Test User",
            groups: [.ops]
        )

        let detailsStream = try await client.user(loginName).details()
        var found = false
        for try await detail in detailsStream {
            #expect(detail.loginName == loginName)
            #expect(detail.fullName == "Details Test User")
            found = true
        }
        #expect(found)

        // Cleanup
        try await client.user(loginName).disable()
    }

    // MARK: - Enable / Disable User

    @Test("It should disable and then enable a user.")
    func testDisableAndEnableUser() async throws {
        let client = KurrentDBClient(settings: settings)
        let loginName = "test-user-\(UUID().uuidString.prefix(8))"

        _ = try await client.users.create(
            loginName: loginName,
            password: "Password123!",
            fullName: "Enable Disable Test",
            groups: [.ops]
        )

        // Disable
        try await client.user(loginName).disable()

        let disabledStream = try await client.user(loginName).details()
        for try await detail in disabledStream {
            #expect(detail.disabled)
        }

        // Enable
        try await client.user(loginName).enable()

        let enabledStream = try await client.user(loginName).details()
        for try await detail in enabledStream {
            #expect(!detail.disabled)
        }
    }

    // MARK: - Update User

    @Test("It should update a user's full name.")
    func testUpdateUserFullName() async throws {
        let client = KurrentDBClient(settings: settings)
        let loginName = "test-user-\(UUID().uuidString.prefix(8))"

        _ = try await client.users.create(
            loginName: loginName,
            password: "Password123!",
            fullName: "Original Name",
            groups: [.ops]
        )

        try await client.user(loginName).update(fullName: "Updated Name", with: "Password123!")

        let detailsStream = try await client.user(loginName).details()
        for try await detail in detailsStream {
            #expect(detail.fullName == "Updated Name")
        }

        // Cleanup
        try await client.user(loginName).disable()
    }

    // MARK: - Change Password

    @Test("It should change a user's password.")
    func testChangePassword() async throws {
        let client = KurrentDBClient(settings: settings)
        let loginName = "test-user-\(UUID().uuidString.prefix(8))"

        _ = try await client.users.create(
            loginName: loginName,
            password: "OldPassword123!",
            fullName: "Password Test",
            groups: [.ops]
        )

        try await client.user(loginName).change(
            password: "NewPassword456!",
            origin: "OldPassword123!"
        )

        // Verify user still exists and is accessible
        let detailsStream = try await client.user(loginName).details()
        for try await detail in detailsStream {
            #expect(detail.loginName == loginName)
        }

        // Cleanup
        try await client.user(loginName).disable()
    }

    // MARK: - Reset Password

    @Test("It should reset a user's password without current password.")
    func testResetPassword() async throws {
        let client = KurrentDBClient(settings: settings)
        let loginName = "test-user-\(UUID().uuidString.prefix(8))"

        _ = try await client.users.create(
            loginName: loginName,
            password: "OriginalPassword123!",
            fullName: "Reset Test",
            groups: [.ops]
        )

        try await client.user(loginName).reset(password: "ResetPassword789!")

        // Verify user still exists and is accessible
        let detailsStream = try await client.user(loginName).details()
        for try await detail in detailsStream {
            #expect(detail.loginName == loginName)
        }

        // Cleanup
        try await client.user(loginName).disable()
    }
}
