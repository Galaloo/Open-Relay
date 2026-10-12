import AVKit
import SwiftUI

/// A compact preview for Open WebUI video files. Both the poster and MP4 use
/// the signed-in API client; the player opens only after an authenticated download.
struct ChatVideoAttachmentView: View {
    let fileID: String
    let posterFileID: String?
    let title: String
    let apiClient: APIClient?

    @State private var poster: UIImage?
    @State private var player: AVPlayer?
    @State private var downloadedVideo: URL?
    @State private var isDownloading = false
    @State private var showPlayer = false
    @State private var errorMessage: String?

    var body: some View {
        Button {
            Task { await openVideo() }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.85))
                if let poster {
                    Image(uiImage: poster)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 240, height: 180)
                        .clipped()
                }
                if isDownloading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                }
            }
            .frame(width: 240, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottomLeading) {
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .padding(8)
                    .shadow(radius: 3)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDownloading)
        .accessibilityLabel("Play video: \(title)")
        .task(id: posterFileID) { await loadPoster() }
        .alert("Video unavailable", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Could not load the video.")
        }
        .fullScreenCover(isPresented: $showPlayer, onDismiss: {
            player?.pause()
            player = nil
            if let downloadedVideo { try? FileManager.default.removeItem(at: downloadedVideo) }
            downloadedVideo = nil
        }) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea(edges: .horizontal)
                }
                Button {
                    player?.pause()
                    showPlayer = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                        .padding()
                }
                .accessibilityLabel("Close video")
            }
        }
    }

    private func loadPoster() async {
        guard let posterFileID, let apiClient else { return }
        do {
            let (data, _) = try await apiClient.getFileContent(id: posterFileID)
            if !Task.isCancelled { poster = UIImage(data: data) }
        } catch {
            // Keep the playable placeholder when an older video has no poster.
        }
    }

    private func openVideo() async {
        guard let apiClient else {
            errorMessage = "Connect to Open WebUI to play this video."
            return
        }
        guard UUID(uuidString: fileID) != nil else {
            errorMessage = "The video has an invalid file reference."
            return
        }
        isDownloading = true
        defer { isDownloading = false }
        do {
            let temporaryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("chat_videos", isDirectory: true)
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            let destination = temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
            let downloaded = try await apiClient.network.downloadFile(path: "/api/v1/files/\(fileID)/content")
            try FileManager.default.moveItem(at: downloaded, to: destination)
            downloadedVideo = destination
            player = AVPlayer(url: destination)
            showPlayer = true
            player?.play()
        } catch {
            errorMessage = "Could not load the video: \(error.localizedDescription)"
        }
    }
}
