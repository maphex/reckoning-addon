# Reckoning

The official guild addon for **&lt;Reckoning&gt;** on **Horde US - Nightslayer (Anniversary)**.

A custom achievement system featuring guild-exclusive challenges, weekly objectives, and progression tracking with Mark of Reckoning currency rewards.

## 📚 Documentation

**[View Full Documentation →](https://larsj02.github.io/Reckoning)**

For comprehensive guides, achievement lists, and detailed information about the addon, visit the official documentation site.

## 🚀 Publishing Releases

This addon uses automated releases via GitHub Actions and [BigWigsMods packager](https://github.com/BigWigsMods/packager).

### How to Publish

1. **Version is auto-managed** - The `@project-version@` placeholder in the TOC file is automatically replaced with the git tag

2. **Changelogs are auto-generated** - Release notes are automatically generated from git commit messages (no manual CHANGELOG.md needed)

3. **Create and push a tag:**

   ```bash
   git tag v0.0.5
   git push origin v0.0.5
   ```

4. **Automated process:**
   - GitHub Actions workflow triggers automatically
   - Packages the addon using BigWigsMods packager
   - Creates a GitHub release with auto-generated changelog
   - Uploads to CurseForge

5. **View releases:**
   - GitHub: [Releases page](https://github.com/jakehobbs/reckoning-addon/releases)
   - CurseForge: [Project page](https://www.curseforge.com/wow/addons/reckoning)
   - GitHub Actions: [Workflow runs](https://github.com/jakehobbs/reckoning-addon/actions)
