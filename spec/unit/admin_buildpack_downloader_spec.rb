require "dea/admin_buildpack_downloader"
require "webmock/rspec"

describe AdminBuildpackDownloader do
  let(:logger) do
    double("logger").as_null_object
  end

  let(:zip_file) do
    File.expand_path("../../fixtures/buildpack.zip", __FILE__)
  end

  let(:destination_directory) { Dir.mktmpdir }

  let(:workspace) { Dir.mktmpdir }

  before do
    stub_request(:any, "http://example.com/buildpacks/uri/abcdef").to_return(
      body: File.new(zip_file)
    )
  end

  after do
    FileUtils.rm_f(destination_directory)
    FileUtils.rm_f(workspace)
  end

  subject(:downloader) do
    AdminBuildpackDownloader.new(buildpacks, destination_directory, workspace, logger)
  end

  context "with single buildpack" do
    let(:buildpacks) do
      [
        {
          "url" => "http://example.com/buildpacks/uri/abcdef",
          "key" => "abcdef"
        }
      ]
    end

    it "downloads the buildpack and unzip it" do
      do_download
      expected_file_name = File.join(destination_directory, "abcdef")
      expect(File.exist?(expected_file_name)).to be_true
      expect(sprintf("%o", File.stat(expected_file_name).mode)).to eq("40755")
      expect(Dir.entries(File.join(destination_directory, "abcdef"))).to include("content")
    end

    it "doesn't download buildpacks it already has" do
      File.stub(:exists?).with(File.join(destination_directory, "abcdef")).and_return(true)
      Download.should_not_receive(:new)
      downloader.download
    end
  end

  context "with multiple buildpacks" do
    let(:buildpacks) do
      [
        {
          "url" => "http://example.com/buildpacks/uri/abcdef",
          "key" => "abcdef"
        },
        {
          "url" => "http://example.com/buildpacks/uri/ijgh",
          "key" => "ijgh"
        }
      ]
    end

    it "only returns when all the downloads are done" do
      stub_request(:any, "http://example.com/buildpacks/uri/ijgh").to_return(
        body: File.new(zip_file)
      )
      do_download
      expect(Dir.entries(File.join(destination_directory))).to include("ijgh")
      expect(Dir.entries(File.join(destination_directory))).to include("abcdef")
      expect(Pathname.new(destination_directory).children).to have(2).items
    end

    it "doesn't throw exceptions if the download fails" do
      stub_request(:any, "http://example.com/buildpacks/uri/ijgh").to_return(
        :status => [500, "Internal Server Error"]
      )
      do_download
      expect(Pathname.new(destination_directory).children).to have(1).item
      expect(Dir.entries(File.join(destination_directory))).to include("abcdef")
    end
  end

  def do_download
    EM.run_block do
      Fiber.new do
        downloader.download
      end.resume
    end
  end
end