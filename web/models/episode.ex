defmodule Changelog.Episode do
  use Changelog.Web, :model
  use Arc.Ecto.Schema

  alias Changelog.Regexp

  schema "episodes" do
    field :slug, :string
    field :title, :string
    field :subtitle, :string
    field :summary, :string
    field :notes, :string
    field :published, :boolean, default: false
    field :published_at, Ecto.DateTime
    field :recorded_at, Ecto.DateTime
    field :guid, :string
    field :audio_file, Changelog.AudioFile.Type
    field :bytes, :integer
    field :duration, :integer

    belongs_to :podcast, Changelog.Podcast
    has_many :episode_hosts, Changelog.EpisodeHost, on_delete: :delete_all
    has_many :hosts, through: [:episode_hosts, :person]
    has_many :episode_guests, Changelog.EpisodeGuest, on_delete: :delete_all
    has_many :guests, through: [:episode_guests, :person]
    has_many :episode_channels, Changelog.EpisodeChannel, on_delete: :delete_all
    has_many :channels, through: [:episode_channels, :channel]
    has_many :episode_sponsors, Changelog.EpisodeSponsor, on_delete: :delete_all
    has_many :sponsors, through: [:episode_sponsors, :sponsor]

    timestamps
  end

  @required_fields ~w(slug title published)
  @optional_fields ~w(subtitle summary notes published_at recorded_at guid)

  def published(query \\ __MODULE__) do
    from e in query, where: e.published == true, where: not(is_nil(e.audio_file))
  end

  def newest_first(query) do
    from e in query, order_by: [desc: e.published_at]
  end

  def changeset(model, params \\ %{}) do
    model
    |> cast(params, @required_fields, @optional_fields)
    |> cast_attachments(params, ~w(audio_file))
    |> validate_format(:slug, Regexp.slug, message: Regexp.slug_message)
    |> unique_constraint(:episodes_slug_podcast_id_index)
    |> cast_assoc(:episode_hosts)
    |> cast_assoc(:episode_guests)
    |> cast_assoc(:episode_sponsors)
    |> cast_assoc(:episode_channels)
    |> derive_bytes_and_duration(params)
  end

  def preload_all(model) do
    model
    |> Repo.preload(:podcast)
    |> Repo.preload([
      episode_hosts: {Changelog.EpisodeHost.by_position, :person},
      episode_guests: {Changelog.EpisodeGuest.by_position, :person},
      episode_sponsors: {Changelog.EpisodeSponsor.by_position, :sponsor},
      episode_channels: {Changelog.EpisodeChannel.by_position, :channel}
    ])
    |> Repo.preload(:hosts)
    |> Repo.preload(:guests)
  end

  defp derive_bytes_and_duration(changeset, params) do
    if new_audio_file = get_change(changeset, :audio_file) do
      # adding the album art to the mp3 file throws off ffmpeg's duration
      # detection (bitrate * filesize). So, we use the raw_file to get accurate
      # duration and the tagged_file to get accurate bytes
      raw_file = params["audio_file"].path
      tagged_file = Changelog.EpisodeView.audio_local_path(%{changeset.model | audio_file: new_audio_file})

      case File.stat(tagged_file) do
        {:ok, stats} ->
          seconds = extract_duration_seconds(raw_file)
          change(changeset, bytes: stats.size, duration: seconds)
        {:error, _} -> changeset
      end
    else
      changeset
    end
  end

  defp extract_duration_seconds(path) do
    try do
      {info, _exit_code} = System.cmd("ffmpeg", ["-i", path], stderr_to_stdout: true)
      [_match, duration] = Regex.run ~r/Duration: (.*?),/, info
      Changelog.TimeView.seconds(duration)
    catch
      _all -> 0
    end
  end
end
