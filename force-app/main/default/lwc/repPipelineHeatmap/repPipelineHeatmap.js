/**
 * repPipelineHeatmap.js
 *
 * Flexible pipeline heatmap component with three view levels:
 *   - Rep       — single user's pipeline
 *   - Territory — all opps in a Territory__c value
 *   - Company   — full company pipeline
 *
 * Works in three page contexts:
 *   1. User Record Page  — automatically filters to that user
 *   2. Home Page         — shows the current user's own pipeline
 *   3. App Page/Tab      — shows pickers (rep/territory based on view level)
 *
 * X-axis : Fiscal quarters (configurable FY start month)
 * Y-axis : Opportunity stages (dynamically derived from data)
 * Metric : Deal count | Total ACV | Weighted pipeline (toggle)
 * Window : Q-1 → Q+3 (5 quarters)
 */
import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue }           from 'lightning/uiRecordApi';
import currentUserId                           from '@salesforce/user/Id';
import USER_NAME                               from '@salesforce/schema/User.Name';
import getOpportunities                        from '@salesforce/apex/PipelineHeatmapController.getOpportunities';
import getOpportunitiesByTerritory             from '@salesforce/apex/PipelineHeatmapController.getOpportunitiesByTerritory';
import getOpportunitiesByCompany               from '@salesforce/apex/PipelineHeatmapController.getOpportunitiesByCompany';
import getSalesReps                            from '@salesforce/apex/PipelineHeatmapController.getSalesReps';
import getTerritories                          from '@salesforce/apex/PipelineHeatmapController.getTerritories';

// ── Constants ──────────────────────────────────────────────────────────────────

/**
 * Preferred stage display order. Stages not in this list are sorted
 * alphabetically and appended after the known ones.
 * Adjust to match your org's opportunity stage picklist values.
 */
const STAGE_ORDER = [
    'Prospecting', 'Qualification', 'Needs Analysis', 'Value Proposition',
    'Id. Decision Makers', 'Perception Analysis', 'Proposal/Price Quote',
    'Negotiation/Review', 'Closed Won'
];

/** Heatmap color ramp endpoints — Axonius orange */
const C_LOW  = [255, 232, 204]; // #FFE8CC — light orange tint
const C_HIGH = [242, 101,  34]; // #F26522 — Axonius orange

// ── Component ──────────────────────────────────────────────────────────────────

export default class RepPipelineHeatmap extends LightningElement {

    // ─── Public @api Properties ──────────────────────────────────────────────

    @api objectApiName;

    /** Fiscal year start month (1–12). Configure in App Builder. Default = January. */
    @api fiscalYearStartMonth = 1;

    /**
     * Show the rep picker dropdown.
     * Enable this when placing the component on an App Page / custom tab.
     */
    @api showRepSelector = false;

    /** Default view level: 'rep', 'territory', or 'company'. Configure in App Builder. */
    @api defaultViewLevel = 'rep';

    /**
     * recordId — declared as a getter/setter so the wire input (_userId)
     * updates reactively when navigating between User records in a console app.
     */
    @api
    get recordId() { return this._recordId; }
    set recordId(val) {
        this._recordId = val;
        if (this.objectApiName === 'User' && val) {
            this._opps   = null; // show loading spinner on navigation
            this._userId = val;
        }
    }

    // ─── Tracked State ───────────────────────────────────────────────────────

    /** The user whose pipeline is displayed (Rep view). Drives data fetch. */
    @track _userId   = currentUserId;

    /**
     * Opportunity data state:
     *   null      → loading (data hasn't resolved yet)
     *   []        → resolved, no data
     *   [...opps] → resolved with data
     */
    @track _opps     = null;

    /** Active metric for cell color + value display */
    @track metric    = 'acv'; // 'count' | 'acv' | 'weighted'

    /** Current view level */
    @track viewLevel = 'rep'; // 'rep' | 'territory' | 'company'

    /** Options list for the rep picker combobox */
    @track repOptions  = [];

    /** Options list for the territory picker combobox */
    @track territoryOptions = [];

    /** Selected territory value */
    @track _territory = null;

    /** Populated on cell hover; cleared on mouse leave */
    @track activeCell  = null;

    // Private backing fields
    _recordId;
    _initialized = false;

    // ─── Wire Adapters ───────────────────────────────────────────────────────

    /** Fetch the User Name to display in the card title when on a User record page */
    @wire(getRecord, { recordId: '$_recordId', fields: [USER_NAME] })
    _wiredUser;

    // ─── Lifecycle ───────────────────────────────────────────────────────────

    connectedCallback() {
        this.viewLevel = this.defaultViewLevel || 'rep';
        this._loadPickerOptions();
        this._loadData();
        this._initialized = true;
    }

    // ─── Data Loading ────────────────────────────────────────────────────────

    _loadPickerOptions() {
        if (this.showRepSelector) {
            getSalesReps()
                .then(reps => {
                    this.repOptions = reps.map(r => ({ label: r.name, value: r.id }));
                })
                .catch(e => console.error('[PipelineHeatmap] getSalesReps error:', JSON.stringify(e)));
        }

        getTerritories({ fyStartMonth: this.fiscalYearStartMonth })
            .then(territories => {
                this.territoryOptions = territories.map(t => ({ label: t, value: t }));
            })
            .catch(e => console.error('[PipelineHeatmap] getTerritories error:', JSON.stringify(e)));
    }

    _loadData() {
        this._opps = null; // show spinner
        this.activeCell = null;

        if (this.viewLevel === 'rep') {
            getOpportunities({ userId: this._userId, fyStartMonth: this.fiscalYearStartMonth })
                .then(data => { this._opps = data; })
                .catch(e => {
                    console.error('[PipelineHeatmap] getOpportunities error:', JSON.stringify(e));
                    this._opps = [];
                });
        } else if (this.viewLevel === 'territory') {
            if (!this._territory) {
                this._opps = [];
                return;
            }
            getOpportunitiesByTerritory({ territory: this._territory, fyStartMonth: this.fiscalYearStartMonth })
                .then(data => { this._opps = data; })
                .catch(e => {
                    console.error('[PipelineHeatmap] getOpportunitiesByTerritory error:', JSON.stringify(e));
                    this._opps = [];
                });
        } else if (this.viewLevel === 'company') {
            getOpportunitiesByCompany({ fyStartMonth: this.fiscalYearStartMonth })
                .then(data => { this._opps = data; })
                .catch(e => {
                    console.error('[PipelineHeatmap] getOpportunitiesByCompany error:', JSON.stringify(e));
                    this._opps = [];
                });
        }
    }

    // ─── Event Handlers ──────────────────────────────────────────────────────

    onViewLevel(event) {
        const level = event.currentTarget.dataset.level;
        if (level === this.viewLevel) return;
        this.viewLevel = level;
        this._loadData();
    }

    onMetric(event) {
        this.metric    = event.currentTarget.dataset.metric;
        this.activeCell = null;
    }

    onRepChange(event) {
        this._userId  = event.detail.value;
        this._loadData();
    }

    onTerritoryChange(event) {
        this._territory = event.detail.value;
        this._loadData();
    }

    onCellEnter(event) {
        const { stage, qid } = event.currentTarget.dataset;
        const row  = this.heatmapRows.find(r => r.stage === stage);
        const cell = row?.cells.find(c => c.qid === qid);
        if (!cell || !cell._src) return;

        const opps    = cell._src;
        const acv     = opps.reduce((s, o) => s + (o.amount || 0), 0);
        const wgt     = opps.reduce((s, o) => s + (o.amount || 0) * ((o.prob || 0) / 100), 0);
        const showOwner = this.viewLevel !== 'rep';

        this.activeCell = {
            header:   `${stage} \u2022 ${cell._qlabel}`,
            count:    opps.length,
            acv:      this._fmt$(acv),
            weighted: this._fmt$(wgt),
            hasDeals: opps.length > 0,
            deals:    opps.slice(0, 6).map(o =>
                showOwner && o.ownerName ? `${o.name} (${o.ownerName})` : o.name
            )
        };
    }

    onCellLeave() {
        this.activeCell = null;
    }

    // ─── Derived Display Properties ──────────────────────────────────────────

    get cardTitle() {
        if (this.viewLevel === 'company') return 'Company';
        if (this.viewLevel === 'territory' && this._territory) return this._territory;
        return '';
    }

    get repName() {
        if (this.viewLevel !== 'rep') return '';
        if (this.objectApiName === 'User' && this._recordId && this._wiredUser?.data) {
            return getFieldValue(this._wiredUser.data, USER_NAME) || '';
        }
        if (this.showRepSelector && this._userId !== currentUserId) {
            return this.repOptions.find(o => o.value === this._userId)?.label || '';
        }
        return '';
    }

    get subtitle() {
        const name = this.cardTitle || this.repName;
        return name ? ` \u2014 ${name}` : '';
    }

    get isLoading()   { return this._opps === null; }
    get showContent() { return !this.isLoading; }
    get hasData()     { return Array.isArray(this._opps) && this._opps.length > 0; }

    // View level button variants
    get repLevelVariant()       { return this.viewLevel === 'rep'       ? 'brand' : 'neutral'; }
    get territoryLevelVariant() { return this.viewLevel === 'territory' ? 'brand' : 'neutral'; }
    get companyLevelVariant()   { return this.viewLevel === 'company'   ? 'brand' : 'neutral'; }

    // Metric button variants
    get countVariant()    { return this.metric === 'count'    ? 'brand' : 'neutral'; }
    get acvVariant()      { return this.metric === 'acv'      ? 'brand' : 'neutral'; }
    get weightedVariant() { return this.metric === 'weighted' ? 'brand' : 'neutral'; }

    // Picker visibility
    get showRepPicker()       { return this.viewLevel === 'rep' && this.showRepSelector; }
    get showTerritoryPicker() { return this.viewLevel === 'territory'; }

    get gridStyle() {
        return `grid-template-columns: 170px repeat(${this.quarters.length}, 1fr);`;
    }

    // ─── Quarter Math ────────────────────────────────────────────────────────

    /**
     * Builds an array of 5 quarter descriptors: Q-1 through Q+3.
     * All date math respects the configured fiscal year start month.
     */
    get quarters() {
        const today   = new Date();
        const fyStart = (Number(this.fiscalYearStartMonth) || 1) - 1; // convert to 0-indexed
        return [-1, 0, 1, 2, 3].map(offset => {
            const { start, end, qNum, yr } = this._qBounds(today, fyStart, offset);
            const isCurrent = (offset === 0);
            return {
                id:        `Q${qNum}-${yr}`,
                label:     `Q${qNum}`,
                sub:       `'${String(yr).slice(2)}`,
                start,
                end,
                isCurrent,
                headerCls: `q-header${isCurrent ? ' q-header--now' : ''}`
            };
        });
    }

    /**
     * Returns { start, end, qNum, yr } for the fiscal quarter at `offset`
     * positions from the quarter containing `date`.
     */
    _qBounds(date, fyStart0, offset) {
        const mo   = date.getMonth();           // 0-indexed
        const mOff = ((mo - fyStart0) + 12) % 12;
        const curQ = Math.floor(mOff / 3);      // 0-indexed FQ within FY
        const fyYr = mo >= fyStart0 ? date.getFullYear() : date.getFullYear() - 1;

        let tgtQ = curQ + offset, tgtYr = fyYr;
        while (tgtQ >= 4) { tgtQ -= 4; tgtYr++; }
        while (tgtQ <  0) { tgtQ += 4; tgtYr--; }

        // Start month (0-indexed) of the target quarter
        let sm = fyStart0 + tgtQ * 3, sy = tgtYr;
        while (sm >= 12) { sm -= 12; sy++; }

        // JS Date overflow trick: day 0 of month M = last day of month M-1
        const start = new Date(sy, sm, 1);
        const end   = new Date(sy, sm + 3, 0);

        return { start, end, qNum: tgtQ + 1, yr: sy };
    }

    // ─── Heatmap Matrix ──────────────────────────────────────────────────────

    /** Unique stage names derived from the data, sorted by STAGE_ORDER then alpha */
    get stages() {
        if (!Array.isArray(this._opps)) return [];
        const seen = [...new Set(this._opps.map(o => o.stage))];
        return seen.sort((a, b) => {
            const ia = STAGE_ORDER.indexOf(a), ib = STAGE_ORDER.indexOf(b);
            if (ia > -1 && ib > -1) return ia - ib;
            if (ia > -1) return -1;
            if (ib > -1) return  1;
            return a.localeCompare(b);
        });
    }

    /** Aggregates `opps` into a single numeric value for the active metric */
    _metricVal(opps) {
        if (this.metric === 'count')    return opps.length;
        if (this.metric === 'acv')      return opps.reduce((s, o) => s + (o.amount || 0), 0);
        /* weighted */                  return opps.reduce((s, o) => s + (o.amount || 0) * ((o.prob || 0) / 100), 0);
    }

    /**
     * Builds the full heatmap row/cell structure consumed by the template.
     * Cell background colors are normalized against the global max value so
     * the darkest cell always represents the highest value in view.
     */
    get heatmapRows() {
        const qs     = this.quarters;
        const stages = this.stages;
        const opps   = this._opps || [];
        if (stages.length === 0) return [];

        // Build raw matrix: stages × quarters
        const raw = stages.map(stage =>
            qs.map(q => {
                const src = opps.filter(o => {
                    // 'T00:00:00' ensures local-date parsing (not UTC midnight drift)
                    const cd = new Date(o.closeDate + 'T00:00:00');
                    return o.stage === stage && cd >= q.start && cd <= q.end;
                });
                return { src, val: this._metricVal(src) };
            })
        );

        // Normalize colors against the global max
        const maxVal = Math.max(...raw.flat().map(c => c.val), 1);

        return stages.map((stage, si) => {
            const rowSum = raw[si].reduce((s, c) => s + c.val, 0);
            return {
                stage,
                rowTotal: this._fmtMetric(rowSum),
                cells: qs.map((q, qi) => {
                    const { src, val } = raw[si][qi];
                    const t     = val / maxVal;          // 0–1 intensity
                    const bg    = val === 0 ? '#f4f6f9' : this._lerp(t);
                    const light = t > 0.52;              // switch to white text above this threshold
                    return {
                        id:       `${stage}||${q.id}`,
                        qid:      q.id,
                        hasValue: val > 0,
                        display:  this._fmtMetric(val),
                        cls:      `data-cell${q.isCurrent ? ' data-cell--now' : ''}`,
                        valCls:   `cell-val${light ? ' cell-val--lt' : ''}`,
                        style:    `background-color:${bg};`,
                        _src:     src,          // kept for the tooltip handler
                        _qlabel:  `${q.label} ${q.sub}`
                    };
                })
            };
        });
    }

    // ─── Utilities ───────────────────────────────────────────────────────────

    /** Linear interpolate between C_LOW and C_HIGH for 0 ≤ t ≤ 1 */
    _lerp(t) {
        const r = Math.round(C_LOW[0] + t * (C_HIGH[0] - C_LOW[0]));
        const g = Math.round(C_LOW[1] + t * (C_HIGH[1] - C_LOW[1]));
        const b = Math.round(C_LOW[2] + t * (C_HIGH[2] - C_LOW[2]));
        return `rgb(${r},${g},${b})`;
    }

    /** Format a metric value for display inside a cell */
    _fmtMetric(val) {
        if (this.metric === 'count') return val === 0 ? '' : String(val);
        return val === 0 ? '' : this._fmt$(val);
    }

    /** Format a dollar amount with M / K suffix */
    _fmt$(val) {
        if (val >= 1e6) return `$${(val / 1e6).toFixed(1)}M`;
        if (val >= 1e3) return `$${(val / 1e3).toFixed(0)}K`;
        return `$${Math.round(val).toLocaleString()}`;
    }
}
