import { LightningElement } from 'lwc';
import loadPage from '@salesforce/apex/PipelineReviewController.loadPage';
import saveNote from '@salesforce/apex/PipelineReviewController.saveNote';
import upsertTag from '@salesforce/apex/PipelineReviewController.upsertTag';
import generateNote from '@salesforce/apex/PipelineReviewController.generateNote';
import saveView from '@salesforce/apex/PipelineReviewSavedViewService.saveView';
import deleteView from '@salesforce/apex/PipelineReviewSavedViewService.deleteView';
import duplicateView from '@salesforce/apex/PipelineReviewSavedViewService.duplicateView';

export default class PipelineReview extends LightningElement {
    loading = true;
    error;
    rows = [];
    aes = [];
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

    connectedCallback() { this.refresh(); }

    get truncated() { return this.loaded !== this.expected && this.expected > 0; }
    get arrLabel() { return '$' + Math.round(this.totalArr || 0).toLocaleString(); }
    get skipLine() {
        const failed = (this.runs || []).find((r) => r.status === 'Failed');
        return failed ? 'Last run failed.' : '';
    }
    get displayRows() {
        const key = this.sortKey;
        const rows = [...(this.rows || [])].map((r) => ({ ...r, selected: this.selected.has(r.id) }));
        rows.sort((a, b) => {
            const av = a[key], bv = b[key];
            if (av === bv) {
                const ta = a.tag || 'Z', tb = b.tag || 'Z';
                if (ta !== tb) return ta.localeCompare(tb);
                return String(a.closeDate || '').localeCompare(String(b.closeDate || ''));
            }
            if (typeof av === 'number' || typeof bv === 'number') return (bv || 0) - (av || 0);
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
                this.views = p.views || [];
                this.expected = p.expected;
                this.loaded = p.loaded;
                this.totalArr = p.totalArr;
                this.lastUpdated = p.lastUpdated;
                this.runs = p.runs || [];
                this.error = undefined;
                if (p.truncated) this.runBanner = 'Loaded ' + p.loaded + ' of ' + p.expected;
            })
            .catch((e) => { this.error = (e.body && e.body.message) || e.message; })
            .finally(() => { this.loading = false; });
    }
    onScope(e) {
        this.filter = { ...this.filter, directorId: e.detail.directorId, teamMode: e.detail.teamMode, productType: e.detail.productType };
        this.refresh();
    }
    onFilter(e) { this.filter = { ...this.filter, ...e.detail }; this.refresh(); }
    onSort(e) { this.sortKey = e.detail; }
    onPick(e) {
        if (e.detail.selected) this.selected.add(e.detail.id);
        else this.selected.delete(e.detail.id);
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
    onRegen() {
        const id = [...this.selected][0];
        if (id) this.onRegenOne({ detail: id });
    }
    onExport() {
        const header = 'Account,AE,Stage,ARR,Close,AE Forecast,Recommended,Grade,Rationale';
        const lines = (this.displayRows || []).map((r) => [r.account, r.ae, r.stage, r.arr, r.closeDate, r.aeForecast, r.recommendedForecast, r.grade, (r.rationale || '').replace(/,/g, ';')].join(','));
        const blob = new Blob([[header, ...lines].join('\n')], { type: 'text/csv' });
        const a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = 'pipeline-review.csv';
        a.click();
    }
    onViewLoad(e) {
        try { this.filter = { ...this.filter, ...JSON.parse(e.detail.definitionJson || '{}') }; this.refresh(); }
        catch (err) { this.error = 'View JSON could not be read.'; }
    }
    onViewSave() {
        const name = window.prompt('View name');
        if (!name) return;
        saveView({ viewId: null, name, definitionJson: JSON.stringify({ v: 1, ...this.filter }), isShared: false, isDefault: false, sortOrder: 1 })
            .then(() => this.refresh());
    }
    onViewDup(e) { if (e.detail) duplicateView({ viewId: e.detail }).then(() => this.refresh()); }
    onViewDel(e) { if (e.detail) deleteView({ viewId: e.detail }).then(() => this.refresh()); }
}
