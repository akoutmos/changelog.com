defmodule Changelog.Repo.Migrations.AddApprovedCommenterColumn do
  use Ecto.Migration

  def change do
    alter table(:people) do
      add(:approved, :boolean, default: true)
    end

    alter table(:news_item_comments) do
      add(:approved, :boolean, default: true)
    end

    create(index(:news_item_comments, [:approved]))
  end
end
