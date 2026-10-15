#!/usr/bin/env node
// Regenerate checked-in icons from the editable SVG; see README.md, App icons.
const fs = require('node:fs/promises');
const path = require('node:path');

async function main() {
    const args = process.argv.slice(2);
    if (args.length === 1 && args[0] === '--help') {
        console.log('Usage: just icons [red|mint|amber|mono]\nColorways come from COLORWAYS in src/app/colorways.odin.\nOmit the colorway to keep the selection saved in Icon.svg.');
        return;
    }
    if (args.length > 1) throw new Error('Usage: just icons [colorway]');
    const root = path.resolve(__dirname, '..');
    const iconset = path.join(root, 'platform/macos/AppIcon.iconset');
    const sourcePath = path.join(iconset, 'Icon.svg');
    let svg = await fs.readFile(sourcePath, 'utf8');
    // Read the flat app palettes directly so icon colors cannot drift from the UI.
    const colorwaysSource = await fs.readFile(path.join(root, 'src/app/colorways.odin'), 'utf8');
    const colorwaysBlock = colorwaysSource.match(/COLORWAYS\s*::[^{]*\{([\s\S]*?)\n\}/);
    if (!colorwaysBlock) throw new Error('Cannot find COLORWAYS in src/app/colorways.odin.');
    const colorways = new Map(Array.from(colorwaysBlock[1].matchAll(
        /\.([A-Z_]+)\s*=\s*\{\s*0x([\dA-F]{6})FF\s*,\s*0x([\dA-F]{6})FF\s*,?\s*\}/gi
    ), ([, name, lit, dark]) => {
        // Match the app's color IDs rather than its internal enum names.
        const id = { vibrant_red: 'red', minty: 'mint' }[name.toLowerCase()] || name.toLowerCase();
        return [id, { lit, dark }];
    }));
    const selected = svg.match(/data-colorway="([a-z_]+)"/);
    if (!selected) throw new Error('Icon.svg must declare its selected data-colorway.');
    const colorway = (args[0] || selected[1]).toLowerCase();
    const palette = colorways.get(colorway);
    if (!palette) throw new Error(`Unknown colorway '${colorway}'. Choose: ${[...colorways.keys()].join(', ')}.`);
    svg = svg.replace(/data-colorway="[a-z_]+"/, `data-colorway="${colorway}"`);
    for (const [stripe, color] of Object.entries(palette)) {
        const marker = new RegExp(`data-stripe="${stripe}" fill="#[\\dA-F]{6}"`, 'gi');
        if ((svg.match(marker) || []).length !== 3) {
            throw new Error(`Icon.svg must mark one ${stripe} stripe fill per band with data-stripe.`);
        }
        svg = svg.replace(marker, `data-stripe="${stripe}" fill="#${color}"`);
    }
    const sharp = require('sharp');
    // Render at 4x the largest output, then downsample for smooth edges at small sizes.
    const desktop = await sharp(Buffer.from(svg), { density: 1152 }).png().toBuffer();
    for (const size of [16, 32, 64, 128, 256, 512]) {
        for (const scale of [1, 2]) {
            const filename = `icon_${size}x${size}${scale === 2 ? '@2x' : ''}.png`;
            await sharp(desktop).resize(size * scale).png().toFile(path.join(iconset, filename));
        }
    }
    await sharp(desktop).resize(128).png().toFile(path.join(root, 'assets/images/icon_128x128.png'));

    // iOS supplies its own corner mask. Android currently derives its launcher icon from this PNG.
    const mobileSvg = svg
        .replace('viewBox="0 0 256 256"', 'viewBox="24 25 206 206"')
        .replace('rx="46"', 'rx="0"');
    const mobile = await sharp(Buffer.from(mobileSvg), { density: 1152 }).png().toBuffer();
    await sharp(mobile).resize(1024).flatten({ background: '#15141B' }).removeAlpha().png()
        .toFile(path.join(root, 'platform/ios/Assets.xcassets/AppIcon.appiconset/AppIcon.png'));
    // Persist the selection and the actual fills so the SVG previews in any viewer.
    await fs.writeFile(sourcePath, svg);
    console.log(`Generated ${colorway} macOS, iOS, and window icons from Icon.svg.`);
}

main().catch(error => {
    console.error(error.code === 'MODULE_NOT_FOUND'
        ? 'Icon generation requires sharp. See README.md, App icons, for installation.'
        : error.message);
    process.exitCode = 1;
});
