// Render wavedrom timing diagram to SVG using jsdom
const wavedrom = require('wavedrom');
const fs = require('fs');
const { JSDOM } = require('jsdom');

const jsonPath = 'D:/Path/RISC-V-TEST/Project/FX-RV32_CUSTOM/doc/NewWork/timing_wavedrom.json';
const svgPath  = 'D:/Path/RISC-V-TEST/Project/FX-RV32_CUSTOM/doc/NewWork/fig_timing_v2.svg';

// Read wavedrom source (JS object format, not JSON)
const jsCode = fs.readFileSync(jsonPath, 'utf8');
const source = eval('(' + jsCode + ')');

// Create virtual DOM
const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>');
global.document = dom.window.document;
global.window   = dom.window;

// Create SVG container element
const container = dom.window.document.createElement('div');
dom.window.document.body.appendChild(container);

// Render the waveform
wavedrom.renderWaveForm(0, source, container);

// Extract SVG string
const svgEl = container.querySelector('svg');
if (svgEl) {
    // Add XML declaration and proper namespace
    let svgStr = svgEl.outerHTML;
    // Ensure xmlns is present
    if (!svgStr.includes('xmlns')) {
        svgStr = svgStr.replace('<svg', '<svg xmlns="http://www.w3.org/2000/svg"');
    }
    // Add width/height for standalone use
    svgStr = svgStr.replace('<svg', '<svg width="800" height="400"');

    const fullSvg = '<?xml version="1.0" encoding="UTF-8"?>\n' + svgStr;
    fs.writeFileSync(svgPath, fullSvg, 'utf8');
    console.log('SVG saved:', fullSvg.length, 'chars');
} else {
    console.log('No SVG found in container');
    console.log('Container HTML:', container.innerHTML.substring(0, 500));
}
