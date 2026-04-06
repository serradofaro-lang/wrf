const state = {
    manifest: null,
    currentDomain: 'd01',
    currentDate: null,
    currentHour: 0,
    currentHourIndex: 0,
    availableHours: [],
    currentVar: 'sfcwind',
    currentZoom: '',
    currentZoom: '',
    // viewType removed
    currentStation: '',

    vectorMode: true, // scalar vs vector vs barb
    layers: {
        clouds: false,
        rain: false,
        takeoffs_names: false
    }
};

const els = {
    dateSelector: document.getElementById('date-selector'),
    domainSelector: document.getElementById('domain-selector'),
    zoomSelector: document.getElementById('zoom-selector'),
    varSelector: document.getElementById('var-selector'),
    hideVarCheckbox: document.getElementById('hide-variable-checkbox'),
    stationSelector: document.getElementById('station-selector'),
    // viewTypeSelector removed
    modeSelector: document.getElementById('mode-selector'),

    // Groups
    zoomGroup: document.getElementById('zoom-group'),
    varGroup: document.getElementById('var-group'),
    stationGroup: document.getElementById('station-group'),
    modeGroup: document.getElementById('mode-group'),
    overlayContainer: document.getElementById('overlay-container'),
    timelineControls: document.querySelector('.timeline-controls'),

    // Images
    imgTerrain: document.getElementById('img-terrain'),
    imgVariable: document.getElementById('img-variable'),
    imgVector: document.getElementById('img-vector'),
    imgRoads: document.getElementById('img-roads'),
    imgRivers: document.getElementById('img-rivers'),
    imgCcaa: document.getElementById('img-ccaa'),
    imgClouds: document.getElementById('img-clouds'),
    imgRain: document.getElementById('img-rain'),
    imgCities: document.getElementById('img-cities'),
    imgPeaks: document.getElementById('img-peaks'),
    imgTakeoffs: document.getElementById('img-takeoffs'),
    imgTakeoffsNames: document.getElementById('img-takeoffs-names'),
    imgSounding: document.getElementById('img-sounding'),
    imgMeteogram: document.getElementById('img-meteogram'),
    imgScale: document.getElementById('img-scale'),

    timeLabel: document.getElementById('current-time-label'),
    lastUpdated: document.getElementById('last-updated'),

};

// --- Initialization ---

async function init() {
    try {
        const resp = await fetch('manifest.json');
        state.manifest = await resp.json();

        // Show last updated
        if (state.manifest.last_updated) {
            els.lastUpdated.textContent = `Actualizado: ${state.manifest.last_updated}`;
        }

        setupControls();
        setupGestures(); // Enable drag/swipe
        // updateViewTypeVisibility(); // Not needed as we don't have view selector
        updateUIForType();
        updateImage();

    } catch (e) {
        console.error("Failed to load manifest", e);
        els.lastUpdated.textContent = "Error cargando datos";
    }
}

function setupGestures() {
    const ids = ['map-container', 'overlay-container'];
    let startX = 0;
    let startY = 0;

    const handleSwipe = (sx, sy, ex, ey) => {
        const diffX = ex - sx;
        const diffY = ey - sy;

        // Check if horizontal swipe dominant and long enough (50px)
        if (Math.abs(diffX) > Math.abs(diffY) && Math.abs(diffX) > 50) {
            if (diffX > 0) {
                // Drag Right -> Prev hour
                stepTime(-1);
            } else {
                // Drag Left -> Next hour
                stepTime(1);
            }
        }
    };

    ids.forEach(id => {
        const el = document.getElementById(id);
        if (!el) return;

        // Touch
        el.addEventListener('touchstart', e => {
            // Stricter check: scale > 1.01
            if (e.touches.length > 1 || (window.visualViewport && window.visualViewport.scale > 1.01)) {
                startX = null;
                startY = null;
                return;
            }
            startX = e.changedTouches[0].screenX;
            startY = e.changedTouches[0].screenY;
        }, { passive: true });

        // Add touchmove to invalidate swipe if it looks like a pan/zoom operation in progress
        el.addEventListener('touchmove', e => {
            if (e.touches.length > 1 || (window.visualViewport && window.visualViewport.scale > 1.01)) {
                startX = null;
                startY = null;
            }
        }, { passive: true });

        el.addEventListener('touchend', e => {
            if (startX === null || startY === null) return; // Invalid start

            // Double check zoom level at end too
            if (window.visualViewport && window.visualViewport.scale > 1.01) {
                startX = null;
                startY = null;
                return;
            }

            const endX = e.changedTouches[0].screenX;
            const endY = e.changedTouches[0].screenY;
            handleSwipe(startX, startY, endX, endY);

            // Reset
            startX = null;
            startY = null;
        }, { passive: true });

        // Mouse
        el.addEventListener('mousedown', e => {
            e.preventDefault(); // Prevent native drag
            startX = e.screenX;
            startY = e.screenY;
        });

        el.addEventListener('mouseup', e => {
            if (startX === null) return;
            handleSwipe(startX, startY, e.screenX, e.screenY);
            startX = null;
            startY = null;
        });
    });
}

function setupControls() {
    // Domains
    els.domainSelector.innerHTML = '';
    state.manifest.domains.forEach((dom, idx) => {
        const btn = document.createElement('button');
        btn.textContent = dom;
        btn.onclick = () => setDomain(dom);
        if (idx === 0) btn.classList.add('active');
        els.domainSelector.appendChild(btn);
    });
    // Set default domain
    if (state.manifest.domains.length > 0) state.currentDomain = state.manifest.domains[0];

    // Dates
    populateDates();

    // Variables (Initial)
    populateVars();

    // Stations (Initial)
    populateStations();

    // Listeners
    els.dateSelector.onchange = (e) => {
        state.currentDate = e.target.value;
        updateAvailableHours();
        updateImage();
    };

    /*
    els.viewTypeSelector.onchange = (e) => {
        state.viewType = e.target.value;
        updateUIForType();
        populateStations(); // Context dependent
        updateImage();
    };
    */

    els.stationSelector.onchange = (e) => {
        state.currentStation = e.target.value;
        updateImage();
    };

    els.varSelector.onchange = (e) => {
        state.currentVar = e.target.value;
        updateModeVisibility();
        updateImage();
    };

    if (els.hideVarCheckbox) {
        els.hideVarCheckbox.onchange = () => {
            updateImage();
        };
    }

    els.zoomSelector.onchange = (e) => {
        state.currentZoom = e.target.value;
        updateModeVisibility();
        updateImage();
    };

    // Toggles (Static)
    // Dynamic Layers from Manifest
    const overlaysGroup = document.getElementById('overlays-group');
    // Clear dynamic toggles but keep static ones if they exist? 
    // Actually the user said "treat in id='overlays-group'".
    // Let's assume we append or clear. Existing static layers are: roads, cities, peaks, takeoffs.
    // They are hardcoded in HTML.

    // Dynamic Layers from Manifest (Exclusive Group - Checkboxes acting as Radio)
    const weatherLayersGroup = document.getElementById('weather-layers');
    if (weatherLayersGroup) {
        weatherLayersGroup.innerHTML = ''; // Clear
        weatherLayersGroup.className = 'checkbox-group'; // Use checkbox styling if available, or keep radio-group

        if (state.manifest.configuration.layers) {
            state.manifest.configuration.layers.forEach(layer => {
                // Initialize state if needed
                if (typeof state.layers[layer.id] === 'undefined') {
                    state.layers[layer.id] = false;
                }

                const div = document.createElement('div');
                div.className = 'checkbox-item'; // or radio-item

                const checkbox = document.createElement('input');
                checkbox.type = 'checkbox';
                checkbox.name = 'weather-layer'; // Name not strictly needed for exclusivity in checkbox, but good for grouping
                checkbox.id = `layer-${layer.id}`;
                checkbox.value = layer.id;
                checkbox.checked = state.layers[layer.id];
                checkbox.dataset.layerId = layer.id;

                // On change, toggle this layer exclusively
                checkbox.onchange = () => {
                    setWeatherLayer(layer.id);
                };

                const label = document.createElement('label');
                label.htmlFor = `layer-${layer.id}`;
                label.textContent = layer.title;

                div.appendChild(checkbox);
                div.appendChild(label);
                weatherLayersGroup.appendChild(div);
            });
        }
    }

    // Static Toggles Listeners
    const toggleTakeoffsNames = document.getElementById('toggle-takeoffs-names');
    if (toggleTakeoffsNames) {
        toggleTakeoffsNames.checked = state.layers.takeoffs_names || false;
        toggleTakeoffsNames.onchange = (e) => {
            state.layers.takeoffs_names = e.target.checked;
            updateImage();
        };
    }

    // Mode
    const modeBtns = els.modeSelector.querySelectorAll('button');
    modeBtns.forEach(btn => {
        btn.onclick = () => {
            if (btn.classList.contains('disabled')) return;
            modeBtns.forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            let val = btn.dataset.value;
            state.vectorMode = val;
            updateImage();
        }
    });

    // Default mode
    state.vectorMode = 'vector';
    updateModeVisibility();

    // Playback
    const prevBtn = document.getElementById('prev-btn');
    const nextBtn = document.getElementById('next-btn');
    if (prevBtn) prevBtn.onclick = () => stepTime(-1);
    if (nextBtn) nextBtn.onclick = () => stepTime(1);

    // Keyboard
    document.addEventListener('keydown', (e) => {
        // if (state.viewType === 'meteogram') return; // Removed restriction
        if (e.key === 'ArrowRight') stepTime(1);
        if (e.key === 'ArrowLeft') stepTime(-1);
    });

    // Responsive Menu
    const menuToggle = document.getElementById('menu-toggle');
    const sidebar = document.querySelector('.sidebar');
    const overlay = document.getElementById('sidebar-overlay');

    if (menuToggle && sidebar) {
        menuToggle.onclick = () => {
            sidebar.classList.toggle('open');
        };
    }

    if (overlay && sidebar) {
        overlay.onclick = () => {
            sidebar.classList.remove('open');
        };
    }
}

function updateUIForType() {
    // Zoom Group: Visible only if Domain has zooms
    const domainZooms = state.manifest.configuration.zooms[state.currentDomain] || [];
    const hasZooms = domainZooms.length > 0;
    els.zoomGroup.classList.toggle('hidden', !hasZooms);

    // Map controls always visible
    els.varGroup.classList.remove('hidden');
    els.modeGroup.classList.toggle('hidden', state.currentZoom === ''); // Will be refined by updateModeVisibility
    document.getElementById('overlays-group').classList.remove('hidden');
    document.getElementById('scale-container').classList.remove('hidden');

    // Station Group: Visible if domain has soundings
    const stationsMap = state.manifest.configuration.soundings || {};
    const stations = stationsMap[state.currentDomain] || [];
    els.stationGroup.classList.toggle('hidden', stations.length === 0);

    // Images Visibility controls
    document.getElementById('map-container').classList.remove('hidden');

    // Sounding/Meteogram Visibility controls
    // If station selected -> Show them
    const showStationPlots = (state.currentStation !== '');
    els.overlayContainer.classList.toggle('hidden', !showStationPlots);

    if (showStationPlots) {
        els.imgSounding.classList.remove('hidden');
        els.imgMeteogram.classList.remove('hidden');
    }

    if (els.timelineControls) {
        els.timelineControls.classList.remove('hidden');
    }

    updateModeVisibility();
}

function updateModeVisibility() {
    // Check if variable is wind
    // if (state.viewType !== 'map') ... removed check
    const WIND_VARS = ['sfcwind', 'wind1500', 'wind2000', 'wind2500', 'wind3000', 'blwind', 'bltopwind'];
    const isWind = WIND_VARS.includes(state.currentVar);
    const hasZoom = state.currentZoom !== '';

    if (!isWind) {
        els.modeGroup.classList.add('hidden');
        return;
    }

    // Is Wind
    if (!hasZoom) {
        // Full Domain Wind -> Only Vector valid -> No choice needed
        els.modeGroup.classList.add('hidden');

        // Ensure we are in vector mode
        if (state.vectorMode !== 'vector') {
            state.vectorMode = 'vector';
            const modeBtns = els.modeSelector.querySelectorAll('button');
            modeBtns.forEach(b => b.classList.toggle('active', b.dataset.value === 'vector'));
        }
    } else {
        // Zoom + Wind -> Choice: Vector or Barb
        els.modeGroup.classList.remove('hidden');

        // Enable/Show Barb button (it might have been hidden by previous logic if we kept it)
        // Actually, logic below handles specific button visibility
        const modeBtns = els.modeSelector.querySelectorAll('button');
        modeBtns.forEach(btn => {
            if (btn.dataset.value === 'barb') {
                // Always show barb if we are here (Zoom + Wind)
                // Unless there's some other constraint? No.
                btn.classList.remove('hidden');
            }
        });
    }
}

function setWeatherLayer(selectedId) {
    const isAlreadyActive = state.layers[selectedId];

    // Set all dynamic layers to false first
    if (state.manifest.configuration.layers) {
        state.manifest.configuration.layers.forEach(layer => {
            state.layers[layer.id] = false;
        });
    }

    // Toggle: if it wasn't active, activate it. If it was active, leave it false (None).
    if (!isAlreadyActive && selectedId) {
        state.layers[selectedId] = true;
    }

    updateWeatherLayerUI(); // Must sync UI manually for checkboxes
    updateImage();
}

function updateWeatherLayerUI() {
    const group = document.getElementById('weather-layers');
    if (!group) return;

    const checkboxes = group.querySelectorAll('input[type="checkbox"]');
    checkboxes.forEach(cb => {
        const layerId = cb.dataset.layerId;
        if (layerId && typeof state.layers[layerId] !== 'undefined') {
            cb.checked = state.layers[layerId];
        }
    });
}

function setDomain(dom) {
    state.currentDomain = dom;

    // Restore map view on domain switch
    // state.viewType = 'map'; // Removed
    // if (els.viewTypeSelector) els.viewTypeSelector.value = 'map'; // Removed

    // Update UI buttons
    Array.from(els.domainSelector.children).forEach(btn => {
        btn.classList.toggle('active', btn.textContent === dom);
    });

    populateVars(); // Zooms depend on domain
    populateStations(); // Stations depend on domain

    // Force UI update to show map
    updateUIForType();

    // updateViewTypeVisibility(); // Removed
    updateModeVisibility();
    updateImage();
}

function populateDates() {
    // Combine Latest + Archive
    const dates = [
        ...state.manifest.dataset_dates.latest,
        ...state.manifest.dataset_dates.archive
    ];

    els.dateSelector.innerHTML = '';
    dates.forEach(d => {
        const opt = document.createElement('option');
        opt.value = d;
        opt.textContent = d;
        els.dateSelector.appendChild(opt);
    });



    if (dates.length > 0) {
        // Try to select Today
        const today = new Date();
        const yyyy = today.getFullYear();
        const mm = String(today.getMonth() + 1).padStart(2, '0');
        const dd = String(today.getDate()).padStart(2, '0');
        const todayStr = `${yyyy}-${mm}-${dd}`;

        if (dates.includes(todayStr)) {
            state.currentDate = todayStr;
        } else {
            // Default to latest available (first in list)
            state.currentDate = dates[0];
        }
        // Sync UI
        els.dateSelector.value = state.currentDate;
    }
    updateAvailableHours();
}

function updateAvailableHours() {
    const date = state.currentDate;
    // Get hours from manifest or default 0..23
    let hours = [];
    if (state.manifest.hours && state.manifest.hours[date]) {
        hours = state.manifest.hours[date];
    }

    // Fallback if empty (e.g. data missing but folder exists?) or manifest older
    if (!hours || hours.length === 0) {
        hours = Array.from({ length: 24 }, (_, i) => i);
    }

    state.availableHours = hours;

    // Default to the first element if no other logic matches
    let newIndex = 0;

    // Reset or clamp index
    const prevHour = state.currentHour;

    // Si la fecha seleccionada es hoy, intentar usar la hora actual + offset utc, o la más cercana anterior
    const today = new Date();
    const yyyy = today.getFullYear();
    const mm = String(today.getMonth() + 1).padStart(2, '0');
    const dd = String(today.getDate()).padStart(2, '0');
    const todayStr = `${yyyy}-${mm}-${dd}`;

    // Si estamos inicializando en el día de hoy o cambiamos al día de hoy, y venimos de prevHour == 0 o primera carga
    if (state.currentDate === todayStr && prevHour === 0) {
        const utcCurrentHour = today.getUTCHours();

        // Buscar la hora más cercana disponible menor o igual a la actual
        // hours[] suele contener timestamps enteros (ej: 0, 1, 2, ..., 23) interpolados
        for (let i = hours.length - 1; i >= 0; i--) {
            if (hours[i] <= utcCurrentHour) {
                newIndex = i;
                break;
            }
        }
    } else {
        // Lógica original: intentar recuperar la hora previa si cambiamos de día
        const foundIndex = hours.indexOf(prevHour);
        if (foundIndex !== -1) {
            newIndex = foundIndex;
        }
    }

    state.currentHourIndex = newIndex;
    state.currentHour = hours[newIndex];

    // Update Slider
    // els.timeSlider.max = hours.length - 1;
    // els.timeSlider.value = newIndex;

    // Update Min/Max Labels
    // document.getElementById('time-min').textContent = getTimeString(hours[0]).substring(0, 2) + ":00" || "00:00";
    // document.getElementById('time-max').textContent = getTimeString(hours[hours.length - 1]).substring(0, 2) + ":00" || "23:00";

    // Hide slider controls if single hour or less
    if (hours.length <= 1) {
        // document.querySelector('.slider-container').classList.add('hidden');
        document.getElementById('prev-btn').classList.add('hidden');
        document.getElementById('next-btn').classList.add('hidden');
    } else {
        // document.querySelector('.slider-container').classList.remove('hidden');
        document.getElementById('prev-btn').classList.remove('hidden');
        document.getElementById('next-btn').classList.remove('hidden');
    }

    updateTimeLabel();
}

/*
function updateViewTypeVisibility() {
    // Logic moved to updateUIForType
}
*/

function populateVars() {
    // Variables
    const vars = state.manifest.configuration.variables || [];
    const currentVar = state.currentVar;

    els.varSelector.innerHTML = '';
    vars.forEach(v => {
        const opt = document.createElement('option');
        opt.value = v.id;
        opt.textContent = v.title || v.id;
        els.varSelector.appendChild(opt);
    });

    // Attempt restore
    if (vars.some(v => v.id === currentVar)) {
        els.varSelector.value = currentVar;
    } else if (vars.length > 0) {
        state.currentVar = vars[0].id;
    }

    // Zooms for Domain
    const domainZooms = state.manifest.configuration.zooms[state.currentDomain] || [];
    const currentZoom = state.currentZoom;

    // Update Mode Visibility based on new var
    updateModeVisibility();

    els.zoomSelector.innerHTML = '<option value="">Dominio Completo</option>';
    domainZooms.forEach(z => {
        const opt = document.createElement('option');
        opt.value = z;
        opt.textContent = z;
        els.zoomSelector.appendChild(opt);
    });

    // Hide zoom selector if no zooms
    if (domainZooms.length === 0) {
        els.zoomGroup.classList.add('hidden');
        state.currentZoom = '';
    } else {
        els.zoomGroup.classList.remove('hidden');
        if (domainZooms.includes(currentZoom)) {
            els.zoomSelector.value = currentZoom;
        } else {
            state.currentZoom = '';
        }
    }
}

function populateStations() {
    const stationsMap = state.manifest.configuration.soundings || {};
    const stations = stationsMap[state.currentDomain] || [];
    const currentSt = state.currentStation;

    els.stationSelector.innerHTML = '';
    stations.forEach(s => {
        const sid = s.id || s;
        const sname = s.name || s;
        const opt = document.createElement('option');
        opt.value = sid;
        opt.textContent = sname;
        els.stationSelector.appendChild(opt);
    });

    if (stations.some(s => (s.id || s) === currentSt)) {
        els.stationSelector.value = currentSt;
    } else if (stations.length > 0) {
        state.currentStation = stations[0].id || stations[0];
        els.stationSelector.value = state.currentStation;
    }
}

// --- Logic ---

function getTimeString(h) {
    return h.toString().padStart(2, '0') + '00';
}

function getBasePath() {
    const base = state.manifest.base_path;
    const dateCompact = state.currentDate.replace(/-/g, ''); // YYYY-MM-DD -> YYYYMMDD
    return `${base}/${state.currentDomain}/${dateCompact}`;
}

function getDomainRootPath() {
    // For static files like terrain, rivers, etc.
    // base / domain
    return `${state.manifest.base_path}/${state.currentDomain}`;
}

function updateImage() {
    if (!state.currentDate) return;

    updateMapImages();

    if (state.currentStation) {
        updateSoundingImage();
        updateMeteogramImage();
    }
}

function updateMapImages() {
    const hhmm = getTimeString(state.currentHour);
    const dayPath = getBasePath(); // Daily folder
    const rootPath = getDomainRootPath(); // Domain root

    const zoomSuffix = state.currentZoom ? `_z${state.currentZoom}` : '';

    // 1. Terrain: terrain[_zZoom].webp (In Domain Root)
    loadImage(els.imgTerrain, `${rootPath}/terrain${zoomSuffix}.webp`);

    // 2. Variable: HHMM_var[_zZoom].webp (Scalar Base)
    const scalarFilename = `${hhmm}_${state.currentVar}${zoomSuffix}.webp`;

    const isVarHidden = els.hideVarCheckbox && els.hideVarCheckbox.checked;
    toggleLayer(els.imgVariable, !isVarHidden, `${dayPath}/${scalarFilename}`);

    // 2b. Vector Overlay: HHMM_var_vec|_barb[_zZoom].webp
    const isWind = ['sfcwind', 'wind1500', 'wind2000', 'wind2500', 'wind3000', 'blwind', 'bltopwind'].includes(state.currentVar);

    if (isWind) {
        let vecSuffix = '';
        if (state.vectorMode === 'vector') vecSuffix = '_vec';
        else if (state.vectorMode === 'barb') vecSuffix = '_barb';

        const vecFilename = `${hhmm}_${state.currentVar}${vecSuffix}${zoomSuffix}.webp`;
        // Only show if not hidden AND we have a valid suffix (mode selected)
        toggleLayer(els.imgVector, (!isVarHidden && vecSuffix), `${dayPath}/${vecFilename}`);
    } else {
        els.imgVector.classList.add('hidden');
    }

    // 2b. Scale: var.webp (Always in Domain Root, NO Zoom suffix usually)
    // Dynamic Layers override currentVar scale if active
    let scaleVar = state.currentVar;
    const dynamicLayers = state.manifest.configuration.layers || [];

    dynamicLayers.forEach(layer => {
        if (state.layers[layer.id]) {
            scaleVar = layer.id;
        }
    });

    loadImage(els.imgScale, `${rootPath}/${scaleVar}.webp`);

    // 3. Static Overlays (Domain Root)
    // rivers, ccaa, roads, cities, peaks, takeoffs
    // These behave like terrain, need zoom suffix
    loadImage(els.imgRivers, `${rootPath}/rivers${zoomSuffix}.webp`);
    loadImage(els.imgCcaa, `${rootPath}/ccaa${zoomSuffix}.webp`);

    // Toggled Overlays
    // Static Overlays (Always Visible)
    loadImage(els.imgRoads, `${rootPath}/roads${zoomSuffix}.webp`);
    loadImage(els.imgCities, `${rootPath}/cities${zoomSuffix}.webp`);
    loadImage(els.imgPeaks, `${rootPath}/peaks${zoomSuffix}.webp`);
    loadImage(els.imgTakeoffs, `${rootPath}/takeoffs${zoomSuffix}.webp`);

    // Optional Overlays
    toggleLayer(els.imgTakeoffsNames, state.layers.takeoffs_names, `${rootPath}/takeoffs_names${zoomSuffix}.webp`);

    // 4. Dynamic Overlays (Daily Folder)
    // dynamicLayers already defined above

    dynamicLayers.forEach(layer => {
        let imgEl = document.getElementById(`img-${layer.id}`);
        if (!imgEl) {
            // Create image element if not exists
            imgEl = document.createElement('img');
            imgEl.id = `img-${layer.id}`;
            imgEl.className = 'map-layer z-40 hidden'; // z-40 matches clouds/rain level
            imgEl.alt = layer.title;
            document.getElementById('map-container').appendChild(imgEl);
        }

        // Construct path
        // Usually: HHMM_id[_zZoom].webp
        const fname = `${hhmm}_${layer.id}${zoomSuffix}.webp`;

        let showLayer = state.layers[layer.id];
        // Special logic: If Rain is active, also show Cloudiness (blcloudpct)
        if (layer.id === 'blcloudpct' && state.layers['rain']) {
            showLayer = true;
        }

        toggleLayer(imgEl, showLayer, `${dayPath}/${fname}`);
    });
}

function updateSoundingImage() {
    // Format: sounding_StationName.webp (Daily? Hourly?)
    // Checking file list: `0000_sounding_station` in daily? NO.
    // Previous code: `sounding_${code}`.
    // Let's assume hourly sounding: `HHMM_sounding_${state.currentStation}.webp` in Daily folder.
    const hhmm = getTimeString(state.currentHour);
    const dayPath = getBasePath();
    // Filename convention for sounding?
    // Warning: Looking at previous `scan_plots` logic: `0000_sounding_station`.
    // So yes: `HHMM_sounding_Name.webp`
    const fname = `${hhmm}_sounding_${state.currentStation}.webp`;
    loadImage(els.imgSounding, `${dayPath}/${fname}`);
}

function updateMeteogramImage() {
    // Meteograms are daily summaries, usually one per day?
    // Filename: `meteogram_${station}.webp` in Daily folder?
    // Re-check scan logic: `meteogram_StationName.webp`.
    // Yes, no HHMM prefix.
    const dayPath = getBasePath();
    const fname = `meteogram_${state.currentStation}.webp`;
    loadImage(els.imgMeteogram, `${dayPath}/${fname}`);
}

function loadImage(imgEl, src) {
    // Simple load with error hiding
    const img = new Image();
    img.onload = () => {
        imgEl.src = src;
        imgEl.classList.remove('hidden');
    };
    img.onerror = () => {
        // imgEl.src = ''; // Clear?
        imgEl.classList.add('hidden'); // Hide if missing
    };
    img.src = src;
}

function toggleLayer(imgEl, show, src) {
    if (show) {
        loadImage(imgEl, src);
    } else {
        imgEl.classList.add('hidden');
    }
}

// --- Time & Animation ---

function updateTimeLabel() {
    const utcHour = getTimeString(state.currentHour).substring(0, 2);

    // Calculate Local Time (UTC + Offset)
    // Assuming browser handles timezone conversion correctly if we construct a UTC date
    // Or we can just use fixed logic if target is specific zone.
    // Better: Construct Date object
    const dateStr = state.currentDate; // YYYY-MM-DD
    const isoStr = `${dateStr}T${utcHour}:00:00Z`;
    const d = new Date(isoStr);

    // Format Local: HH:00
    const localHour = String(d.getHours()).padStart(2, '0');

    els.timeLabel.textContent = `${localHour}:00`;
}

function stepTime(dir) {
    let newIdx = state.currentHourIndex + dir;
    const max = state.availableHours.length;

    // Check if we need to change day
    if (newIdx >= max || newIdx < 0) {
        // Find current date index
        const dates = Array.from(els.dateSelector.options).map(o => o.value);
        const currentDateIdx = dates.indexOf(state.currentDate);

        // Determine next date index
        // dates are usually sorted Descending (Latest -> Archive)? 
        // populateDates sorts: Latest + Archive.
        // scan_availability sorts: Latest (Desc?), Archive (Desc?).
        // If dates are [2026-02-18, 2026-02-17], then index 0 is tomorrow, index 1 is today.
        // We need to check the actual date values to be sure or rely on the list order.
        // Let's assume the list is [Future...Today...Past].
        // Next Day (Time forward) -> value > current or index - 1?
        // Wait, "Next Day" means Time + 24h.
        // If list is sorted Descending (Newest first):
        //   Forward in time -> Move to a date that is "newer" than current? No.
        //   Forward in time -> Move to Next Calendar Day.

        // Let's do robust date math.
        const currentDt = new Date(state.currentDate);
        const nextDt = new Date(currentDt);
        if (dir > 0) {
            // Forward -> Next Day
            nextDt.setDate(currentDt.getDate() + 1);
        } else {
            // Backward -> Prev Day
            nextDt.setDate(currentDt.getDate() - 1);
        }

        const yyyy = nextDt.getFullYear();
        const mm = String(nextDt.getMonth() + 1).padStart(2, '0');
        const dd = String(nextDt.getDate()).padStart(2, '0');
        const nextDateStr = `${yyyy}-${mm}-${dd}`;

        if (dates.includes(nextDateStr)) {
            // Switch Date
            state.currentDate = nextDateStr;
            els.dateSelector.value = nextDateStr;
            updateAvailableHours();

            // Set hour
            if (dir > 0) {
                // Moving Forward: Came from end of prev day -> Start of new day
                state.currentHourIndex = 0;
            } else {
                // Moving Backward: Came from start of next day -> End of prev day
                state.currentHourIndex = state.availableHours.length - 1;
            }
            state.currentHour = state.availableHours[state.currentHourIndex];
        } else {
            // No next/prev day available -> Loop within current day
            if (newIdx >= max) newIdx = 0;
            if (newIdx < 0) newIdx = max - 1;
            state.currentHourIndex = newIdx;
            state.currentHour = state.availableHours[newIdx];
        }
    } else {
        // Within same day
        state.currentHourIndex = newIdx;
        state.currentHour = state.availableHours[newIdx];
    }

    updateTimeLabel();
    updateImage();
}



// Start
init();
