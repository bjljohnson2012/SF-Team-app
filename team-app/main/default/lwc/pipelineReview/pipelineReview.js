import { LightningElement } from 'lwc';
import loadPage from '@salesforce/apex/PipelineReviewController.loadPage';
import saveNote from '@salesforce/apex/PipelineReviewController.saveNote';
import upsertTag from '@salesforce/apex/PipelineReviewController.upsertTag';
import generateNote from '@salesforce/apex/PipelineReviewController.generateNote';
import enqueueGrade from '@salesforce/apex/PipelineReviewController.enqueueGrade';
import saveView from '@salesforce/apex/PipelineReviewSavedViewService.saveView';
import deleteView from '@salesforce/apex/PipelineReviewSavedViewService.deleteView';

const STAGE_SEED = [
    'Prospecting', 'Identify', 'Discovery', 'Qualification', 'Alignment',
    'Proposal', 'Negotiation', 'Verbal Win', 'Signature Pending', 'Contract'
];

export default class PipelineReview extends LightningElement {
    loading = true;
    error;
    rows = [];
    aes = [];
    directors = [];
    views = [];
    expected = 0;
    loaded = 0;
    totalArr = 0;
    lastUpdated;
    filter = {};
    selected = new Set();
    sortKey = 'arr';
    drawer;
    preview;
    drawerError;
    runBanner;
    runs = [];
    onlyChanged = false;
    chipFilter;
    thresholdPct = 2;
    quota = 761000;
    period = 'thisNext';
    gradeOnRefresh = false;

    connectedCallback() { this.refresh(); }

    get truncated() { return this.loaded !== this.expected && this.expected > 0; }
    get doneToday() {
        const today = this.todayIso();
        return (this.rows || []).filter((r) => r.noteUpdatedOn && String(r.noteUpdatedOn).slice(0, 10) === today).length;
    }
    get notRun() { return (this.rows || []).filter((r) => !r.grade).length; }
    get pushedToday() { return 0; }
    get runStatus() {
        const running = (this.runs || []).find((r) => r.status === 'Running' || r.status === 'Queued');
        if (running) return running.status;
        const failed = (this.runs || []).find((r) => r.status === 'Failed');
        return failed ? 'Failed' : 'Idle';
    }
    get skipLine() {
        const failed = (this.runs || []).find((r) => r.status === 'Failed');
        return failed ? 'Last run failed.' : '';
    }
    get stageOptions() {
        const fromRows = (this.rows || []).map((r) => r.stage).filter(Boolean);
        return [...new Set([...STAGE_SEED, ...fromRows])].sort();
    }
    get solutionOptions() {
        return [...new Set((this.rows || []).map((r) => r.solution).filter(Boolean))].sort();
    }
    get stats() {
        const visible = this.displayRows;
        const all = this.rows || [];
        const gradeOf = (r) => (r.tag || r.grade || '').toUpperCase();
        const count = (g) => all.filter((r) => gradeOf(r) === g).length;
        const arr = all.reduce((s, r) => s + (Number(r.arr) || 0), 0);
        const today = this.todayIso();
        return {
            openArr: this.money(arr),
            opps: visible.length + ' / ' + all.length,
            loaded: this.loaded + ' / ' + (this.expected || this.loaded),
            a: count('A'),
            b: count('B'),
            c: count('C'),
            d: count('D'),
            mismatches: rows.filter((r) => r.mismatch).length,
            changed: rows.filter((r) => r.noteUpdatedOn && String(r.noteUpdatedOn).slice(0, 10) === today).length,
            doneToday: this.doneToday + ' / ' + all.length,
            pushedToday: this.pushedToday + ' / ' + all.length,
            chip: this.chipFilter || '',
            summary: this.thresholdSummary(all, rows)
        };
    }
    get displayRows() {
        const key = this.sortKey;
        const today = this.todayIso();
        let rows = [...(this.rows || [])].map((r) => ({ ...r, selected: this.selected.has(r.id) }));
        if (this.filter.tags && this.filter.tags.length) {
            const want = new Set(this.filter.tags.map((t) => String(t).toUpperCase()));
            rows = rows.filter((r) => want.has(String(r.tag || r.grade || '').toUpperCase()) || (want.has('UNTAGGED') && !r.tag && !r.grade));
        }
        if (this.filter.staleness && this.filter.staleness.length) {
            const want = new Set(this.filter.staleness);
            rows = rows.filter((r) => want.has(this.ageBand(r.freshestAge)));
        }
        if (this.filter.runStates && this.filter.runStates.length) {
            const want = new Set(this.filter.runStates);
            rows = rows.filter((r) => want.has(this.runState(r, today)));
        }
        if (this.onlyChanged) {
            rows = rows.filter((r) => r.noteUpdatedOn && String(r.noteUpdatedOn).slice(0, 10) === today);
        }
        if (this.chipFilter === 'mismatch') rows = rows.filter((r) => r.mismatch);
        else if (this.chipFilter) {
            const g = this.chipFilter.toUpperCase();
            rows = rows.filter((r) => String(r.tag || r.grade || '').toUpperCase() === g);
        }
        rows.sort((a, b) => {
            const av = a[key], bv = b[key];
            if (av === bv) {
                const ta = a.tag || a.grade || 'Z', tb = b.tag || b.grade || 'Z';
                if (ta !== tb) return ta.localeCompare(tb);
                return String(a.closeDate || '').localeCompare(String(b.closeDate || ''));
            }
            if (typeof av === 'number' || typeof bv === 'number') return (Number(bv) || 0) - (Number(av) || 0);
            return String(bv || '').localeCompare(String(av || ''));
        });
        return rows;
    }

    refresh() {
        this.loading = true;
        loadPage({ filterJson: JSON.stringify(this.filter) })
            .then((p) => {
                this.rows = p.rows || [];
                this.aes = p.aes || [];
                this.directors = p.directors || [];
                this.views = p.views || [];
                this.expected = p.expected;
                this.loaded = p.loaded;
                this.totalArr = p.totalArr;
                this.lastUpdated = p.lastUpdated;
                this.runs = p.runs || [];
                this.error = undefined;
                if (p.truncated) this.runBanner = 'Loaded ' + p.loaded + ' of ' + p.expected;
                else this.runBanner = undefined;
            })
            .catch((e) => { this.error = (e.body && e.body.message) || e.message; })
            .finally(() => { this.loading = false; });
    }
    onFilter(e) { this.filter = { ...this.filter, ...e.detail }; this.refresh(); }
    onSort(e) { this.sortKey = e.detail; }
    onPick(e) {
        if (e.detail.selected) this.selected.add(e.detail.id);
        else this.selected.delete(e.detail.id);
        this.selected = new Set(this.selected);
    }
    onPickAll(e) {
        if (e.detail.selected) this.displayRows.forEach((r) => this.selected.add(r.id));
        else this.displayRows.forEach((r) => this.selected.delete(r.id));
        this.selected = new Set(this.selected);
    }
    onTag(e) { upsertTag({ opportunityId: e.detail.id, tag: e.detail.tag }).then(() => this.refresh()); }
    onOpen(e) { this.drawer = e.detail; this.preview = undefined; this.drawerError = undefined; }
    onClose() { this.drawer = undefined; }
    onSaveNote(e) {
        saveNote({ opportunityId: e.detail.id, note: e.detail.note, aiGenerated: false })
            .then((r) => { if (!r.ok) this.drawerError = r.error; else this.refresh(); });
    }
    onRegenOne(e) {
        generateNote({ opportunityId: e.detail, persist: false })
            .then((g) => { this.preview = g.note; this.drawerError = g.error; });
    }
    onExport() {
        const header = 'Account,Opportunity,AE,Stage,Solution,ARR,Close,AE Forecast,Director Forecast,Recommended,Grade,Tag,Note';
        const lines = (this.displayRows || []).map((r) => [
            r.account, r.name, r.ae, r.stage, r.solution, r.arr, r.closeDate,
            r.aeForecast, r.directorForecast, r.recommendedForecast, r.grade, r.tag,
            (r.note || '').replace(/,/g, ';').replace(/\n/g, ' ')
        ].join(','));
        const blob = new Blob([[header, ...lines].join('\n')], { type: 'text/csv' });
        const a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = 'pipeline-review.csv';
        a.click();
    }
    onViewLoad(e) {
        try { this.filter = { ...(JSON.parse(e.detail.definitionJson || '{}')) }; this.refresh(); }
        catch (err) { this.error = 'View JSON could not be read.'; }
    }
    onViewSave() {
        const name = window.prompt('View name');
        if (!name) return;
        saveView({ viewId: null, name, definitionJson: JSON.stringify({ v: 1, ...this.filter }), isShared: false, isDefault: false, sortOrder: 1 })
            .then(() => this.refresh());
    }
    onViewDel(e) { if (e.detail) deleteView({ viewId: e.detail }).then(() => this.refresh()); }
    onViewReset() {
        this.filter = {};
        this.onlyChanged = false;
        this.chipFilter = undefined;
        this.refresh();
    }
    onViewRefresh() {
        this.refresh();
        if (this.gradeOnRefresh) this.maybeEnqueue();
    }
    onOnlyChanged(e) { this.onlyChanged = e.detail === true; }
    onChip(e) {
        const next = e.detail;
        this.chipFilter = this.chipFilter === next ? undefined : next;
    }
    onThreshold(e) {
        if (e.detail.thresholdPct != null) this.thresholdPct = Number(e.detail.thresholdPct) || 0;
        if (e.detail.quota != null) this.quota = Number(e.detail.quota) || 0;
        if (e.detail.period != null) this.period = e.detail.period;
        if (e.detail.gradeOnRefresh != null) this.gradeOnRefresh = e.detail.gradeOnRefresh === true;
    }
    onGradeKey() { this.maybeEnqueue(); }
    onGradeSelected() {
        const id = [...this.selected][0];
        if (id) this.onRegenOne({ detail: id });
        else this.maybeEnqueue();
    }
    onClearGrades() {
        const ids = this.selected.size ? [...this.selected] : this.displayRows.map((r) => r.id);
        Promise.all(ids.slice(0, 50).map((id) => upsertTag({ opportunityId: id, tag: '' })))
            .then(() => this.refresh());
    }
    maybeEnqueue() {
        enqueueGrade()
            .then(() => { this.runBanner = 'Grade job queued.'; })
            .catch((e) => { this.runBanner = (e.body && e.body.message) || e.message; });
    }
    todayIso() { return new Date().toISOString().slice(0, 10); }
    money(n) { return '$' + Math.round(n || 0).toLocaleString(); }
    ageBand(days) {
        if (days == null) return 'unknown';
        if (days <= 7) return 'current';
        if (days <= 21) return 'recent';
        if (days <= 45) return 'aging';
        return 'history';
    }
    runState(r, today) {
        if (!r.grade && !r.gradeComputedOn) return 'never';
        if (r.gradeComputedOn && String(r.gradeComputedOn).slice(0, 10) === today) return 'today';
        if (r.gradeComputedOn) return 'stale';
        return 'never';
    }
    thresholdSummary(all, rows) {
        const floor = (this.quota || 0) * ((this.thresholdPct || 0) / 100);
        const key = (all || []).filter((r) => (Number(r.arr) || 0) >= floor);
        const keyArr = key.reduce((s, r) => s + (Number(r.arr) || 0), 0);
        const graded = (all || []).filter((r) => r.grade).length;
        const pending = (all || []).length - graded;
        return 'Threshold $' + Math.round(floor).toLocaleString()
            + ' — ' + key.length + ' deals worth ' + this.money(keyArr)
            + ' — ' + graded + ' graded, ' + pending + ' pending'
            + ' — ' + (rows || []).length + ' visible.';
    }
}
