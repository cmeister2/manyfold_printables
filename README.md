# Printables for Manyfold

Link Manyfold models to Printables, find fuzzy matches with public search, and sync model and creator details and images.

## Install

Requires Manyfold 0.146.0 or newer. Linking models and creators requires administrator access.

1. Download `manyfold_printables.zip` from the [latest release](https://github.com/cmeister2/manyfold_printables/releases/latest).
2. Upload the ZIP under **Settings > Plugins**, then restart Manyfold. Keep the ZIP filename unchanged when installing updates.
3. Printables linking is enabled by default. You can switch it off under **Settings > Integrations**. Create a Manyfold library if you do not have one.

See Manyfold's [plugin installation guide](https://manyfold.app/sysadmin/plugins) for plugin directory setup.

## Link models

Choose **Link to Printables** from an existing Manyfold model's menu. The page searches Printables using the model's name and ranks close matches. Adjust the search text if needed, then select **Use this model**. You can also enter a public model URL such as `https://www.printables.com/model/12345`, or its numeric ID. Select **Link and sync** to queue metadata and image sync.

No Printables login or API credentials are required. This action appears when the Printables integration is enabled. Search failures leave the manual URL input available.

You can also use Manyfold's **Add content > Import URL** with a public Printables model URL to create a new Manyfold model through its normal import flow. Sync imports details and images; download 3D model files from Printables and import them into Manyfold separately.

The integration uses Printables' GraphQL interface. Its automated tests use fictional API responses.

## Sync creators

On the **Creators** page, choose **Link to Printables** from a creator's menu, select one of their linked models, and choose **Link and sync**. The plugin uses that model to find the Printables profile and sync the existing creator's name, biography, avatar, and banner. It preserves their ownership and model associations.

The action requires the Printables integration to be enabled and administrator access, a visible Printables-linked model assigned to the creator, and no existing Printables profile link. Printables profiles use URLs such as `https://www.printables.com/@example-studio`. Once linked, use Manyfold's normal **Synchronize** action to refresh the profile.

## Provider navigation

The plugin adds Printables to a shared **Providers** dropdown. The menu helper is bundled, so no additional plugin is required.

Other provider plugins can bundle `lib/manyfold/provider_menu.rb` unchanged and register their menu item after Rails initializes:

```ruby
require "manyfold/provider_menu"
Manyfold::ProviderMenu.register(Components::ExampleProvider::MenuItem)
```

The component supplies a class method `label` and renders a Manyfold `DropdownItem` with its own icon and route. Entries are sorted by label. Ruby loads one copy of the helper, and repeated registration creates one dropdown. An optional class method `visible?(view_context)` controls visibility for the current request; an empty menu is hidden.

Keep the shared helper API compatible across providers: Ruby uses the first bundled copy on its load path.

## Local development

With Docker Compose installed, run from the repository root:

```sh
docker compose up --build -d
```

Open <http://localhost:3214>. The container uses single-user mode and creates an administrator and a default library automatically. Data persists in the Compose volume.

After changing Ruby code or templates, reload the application with:

```sh
docker compose restart manyfold
```

## Tests

With Python 3 and Docker installed:

```sh
bin/test
```

This runs package checks, then the plugin suite against both the source tree and an extracted ZIP. It checks the version loaded by Manyfold from the packaged gemspec. Each container uses a disposable database and Redis; temporary files and containers are cleaned up afterward.

Release tooling tests require Node 24.15 or newer:

```sh
npm ci --ignore-scripts
npm run test:release
```

## Releases

Semantic-release publishes from `main` using Conventional Commits: `fix:` produces a patch release, `feat:` a minor release, and a breaking change a major release.

The source gemspec stays at `0.0.0`. The release prepare step writes the calculated version into the gemspec inside `manyfold_printables.zip`.

Pull requests and manual CI runs preview the proposed release without publishing. You can run the same preview locally:

```sh
npm run release:dry-run
```

The preview uses a temporary local Git remote and needs no GitHub credentials. It analyses commits and renders release notes; release preparation and publishing run only on a push to `main`.

To build a ZIP locally with a specific version:

```sh
python3 bin/package 0.1.0
```

The archive is written to `dist/manyfold_printables.zip`.
