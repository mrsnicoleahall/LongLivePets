# Installing Long Live Pets

Long Live Pets ships as **two addon folders** that both sit directly inside your
WoW `AddOns` folder:

- **`LongLivePets`** — the addon itself
- **`tdBattlePetScript`** — the optional, bundled battle-script engine (MIT, by DengSir)

## Steps

1. Go to the [latest release](https://github.com/mrsnicoleahall/LongLivePets/releases/latest)
   and download the **`LongLivePets-x.y.z.zip`** asset.

   > ⚠️ **Don't** download "Source code (zip)". GitHub names that folder after the
   > version (e.g. `LongLivePets-0.19.2-alpha`) and tucks `tdBattlePetScript`
   > inside it — WoW won't load either one. The `LongLivePets-x.y.z.zip` asset is
   > already laid out correctly.

2. Unzip it. You'll see two folders: `LongLivePets` and `tdBattlePetScript`.

3. Copy **both** folders into your AddOns directory:
   - **Windows:** `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns`
   - **macOS:** `/Applications/World of Warcraft/_retail_/Interface/AddOns`

   When you're done it should look like this:

   ```
   Interface/AddOns/
   ├── LongLivePets/
   │   └── LongLivePets.toc
   └── tdBattlePetScript/
       └── tdBattlePetScript.toc
   ```

   Each folder must sit **directly** inside `AddOns` — not nested inside another
   folder. WoW needs to see `AddOns/LongLivePets/LongLivePets.toc`.

4. Launch WoW, enable both addons on the character-select **AddOns** screen, and
   log in. Type `/llp` to open Long Live Pets.

## Notes

- **Just want the team manager, no scripts?** You can install only `LongLivePets`
  and skip `tdBattlePetScript`.
- **Already run a standalone `tdBattlePetScript`?** Keep just one copy to avoid a
  duplicate.
- **Folder still won't show up?** Double-check the folder is named exactly
  `LongLivePets` (no version suffix) and that the `.toc` sits directly inside it.
