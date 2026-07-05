import SwiftUI

/// Third-party acknowledgements, presented as a modal sheet from the quiet footer link at the
/// bottom of ``SettingsView``. Discloses the licenses the app is obligated to reproduce — the
/// SIL OFL icon glyphs extracted from Baby Buddy's Fontello font, and the bundled MIT SDKs —
/// and credits the upstream open-source Baby Buddy project with a link to its repository.
struct AcknowledgementsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    aboutCard
                    ForEach(Acknowledgement.all) { notice in
                        noticeCard(notice)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(BBColor.surface)
            .navigationTitle("Acknowledgements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Baby Buddy credit

    /// A short credit to the upstream open-source project, with a link out to its GitHub.
    private var aboutCard: some View {
        BBCard(cornerRadius: BBRadius.tile) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Based on Baby Buddy")
                    .font(.system(size: 16, weight: .semibold))
                Text("Baby Buddy for iOS is an unofficial client for the open-source Baby Buddy "
                     + "baby-tracking server, and is not affiliated with that project. "
                     + "Thanks to its maintainers and contributors.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                repoLink
            }
        }
    }

    private var repoLink: some View {
        Button { openURL(AcknowledgementLinks.babyBuddyRepo) } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                Text("github.com/babybuddy/babybuddy")
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(BBColor.brandAccent)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    // MARK: Notice card

    /// One third-party notice: name, license short-name, and the verbatim license text (selectable
    /// so it can be copied) in a compact monospaced block.
    private func noticeCard(_ notice: Acknowledgement) -> some View {
        BBCard(cornerRadius: BBRadius.tile) {
            VStack(alignment: .leading, spacing: 6) {
                Text(notice.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(notice.license)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BBColor.brandAccent)
                Text(notice.text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - Links

enum AcknowledgementLinks {
    static let babyBuddyRepo = URL(string: "https://github.com/babybuddy/babybuddy")!
}

// MARK: - Notice data

/// A single reproduced third-party license notice shown on ``AcknowledgementsView``.
private struct Acknowledgement: Identifiable {
    let id = UUID()
    let title: String
    let license: String
    let text: String

    static let all: [Acknowledgement] = [icons, babyBuddy, revenueCat, telemetryDeck]

    /// The activity/measurement glyphs are outlines extracted from Baby Buddy's Fontello icon
    /// font, which bundles three icon sets — all under the SIL Open Font License 1.1.
    static let icons = Acknowledgement(
        title: "App icons — Font Awesome, MFG Labs & Entypo",
        license: "SIL Open Font License 1.1",
        text: """
        The activity and measurement glyphs are extracted from the Baby Buddy \
        project's Fontello icon font, which bundles:

          • Font Awesome — Copyright (C) 2016 by Dave Gandy
          • MFG Labs — Copyright (C) 2012 by Daniel Bruce
          • Entypo — Copyright (C) 2012 by Daniel Bruce

        Each is licensed under the SIL Open Font License, Version 1.1.

        Permission is hereby granted, free of charge, to any person obtaining a \
        copy of the Font Software, to use, study, copy, merge, embed, modify, \
        redistribute, and sell modified and unmodified copies of the Font \
        Software, subject to the following conditions:

        1) Neither the Font Software nor any of its individual components, in \
        Original or Modified Versions, may be sold by itself.

        2) Original or Modified Versions of the Font Software may be bundled, \
        redistributed and/or sold with any software, provided that each copy \
        contains the above copyright notice and this license.

        3) No Modified Version of the Font Software may use the Reserved Font \
        Name(s) unless explicit written permission is granted by the \
        corresponding Copyright Holder.

        4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font \
        Software shall not be used to promote, endorse or advertise any Modified \
        Version, except to acknowledge the contribution(s) of the Copyright \
        Holder(s) and the Author(s) or with their explicit written permission.

        5) The Font Software, modified or unmodified, in part or in whole, must \
        be distributed entirely under this license, and must not be distributed \
        under any other license.

        THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, \
        EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF \
        MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF \
        COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE \
        COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, \
        INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL \
        DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING \
        FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM OTHER \
        DEALINGS IN THE FONT SOFTWARE.

        The full license is available at https://scripts.sil.org/OFL
        """)

    static let babyBuddy = Acknowledgement(
        title: "Baby Buddy",
        license: "BSD 2-Clause License",
        text: """
        Copyright (c) 2017 - 2022, Baby Buddy's Contributors
        All rights reserved.

        Redistribution and use in source and binary forms, with or without \
        modification, are permitted provided that the following conditions are \
        met:

        * Redistributions of source code must retain the above copyright \
        notice, this list of conditions and the following disclaimer.

        * Redistributions in binary form must reproduce the above copyright \
        notice, this list of conditions and the following disclaimer in the \
        documentation and/or other materials provided with the distribution.

        THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS \
        "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT \
        LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A \
        PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT \
        HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, \
        SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED \
        TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR \
        PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF \
        LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING \
        NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS \
        SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
        """)

    static let revenueCat = Acknowledgement(
        title: "RevenueCat (purchases-ios)",
        license: "MIT License",
        text: mitLicense(copyright: "Copyright (c) 2024 RevenueCat, Inc."))

    static let telemetryDeck = Acknowledgement(
        title: "TelemetryDeck (SwiftSDK)",
        license: "MIT License",
        text: mitLicense(copyright: "Copyright (c) 2020 Daniel Jilg"))

    private static func mitLicense(copyright: String) -> String {
        """
        \(copyright)

        Permission is hereby granted, free of charge, to any person obtaining a \
        copy of this software and associated documentation files (the \
        "Software"), to deal in the Software without restriction, including \
        without limitation the rights to use, copy, modify, merge, publish, \
        distribute, sublicense, and/or sell copies of the Software, and to \
        permit persons to whom the Software is furnished to do so, subject to \
        the following conditions:

        The above copyright notice and this permission notice shall be included \
        in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS \
        OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF \
        MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. \
        IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY \
        CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, \
        TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE \
        SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
    }
}
