# frozen_string_literal: true

require "base64"
require "tempfile"

class PrintablesPluginTest
  def test_model_sync_preserves_a_local_image_with_the_same_provider_basename
    with_native_model do |model|
      downloads = []
      with_image_download(downloads) do
        local = model.create_or_update_file_from_url(url: "https://example.invalid/local-preview.png", filename: "preview.png")
        local_data = local.reload.attachment_data
        local_path = File.join(@library_path, model.path, "preview.png")
        local_contents = File.binread(local_path)
        downloads.clear
        payload = fake_link_payload.merge("image" => {"filePath" => "media/prints/92001/images/preview.png"})
        with_link_client(FakeLinkClient.new(payload)) do
          ManyfoldPrintables::SyncJob.perform_now(model.id, @users.first.id, "92001")
        end
        remote = model.model_files.find_by!(filename: "images/printables/preview.png")
        assert_equal 2, model.model_files.count
        refute_equal local.id, remote.id
        assert_equal local_data, local.reload.attachment_data
        assert_equal local_contents, File.binread(local_path)
        assert local.attachment.exists?
        assert remote.attachment.exists?
        assert_equal remote.id, model.reload.preview_file_id
        assert_equal ["https://media.printables.com/media/prints/92001/images/preview.png"], downloads
      end
    end
  end

  private

  def with_image_download(downloads)
    singleton = Down.singleton_class
    original_download = Down.method(:download)
    temporary_files = []
    # One white PNG pixel exercises Shrine's normal upload and preview pipeline.
    png = Base64.strict_decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC")
    singleton.send(:define_method, :download) do |url, **options|
      downloads << url
      file = Tempfile.new(["fictional-printables-image-", ".png"])
      file.binmode
      file.write(png)
      file.rewind
      file.define_singleton_method(:original_filename) { "fictional-preview.png" }
      temporary_files << file
      file
    end
    yield
  ensure
    singleton.send(:define_method, :download, original_download)
    temporary_files.each(&:close!)
  end

end
