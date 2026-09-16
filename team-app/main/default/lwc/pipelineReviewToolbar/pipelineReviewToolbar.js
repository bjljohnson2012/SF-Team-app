import { LightningElement, api } from 'lwc';
export default class PipelineReviewToolbar extends LightningElement {
    @api lastUpdated;
    @api banner;
    @api skipLine = '';
    @api stats;
    @api thresholdPct = 2;
    @api quota = 761000;
    @api period = 'thisNext';
    @api gradeOnRefresh = false;

    get lastUpdatedLabel() {
        return this.lastUpdated ? new Date(this.lastUpdated).toLocaleString() : 'not yet graded';
    }
    get summary() { return (this.stats && this.stats.summary) || ''; }
    get openArr() { return (this.stats && this.stats.openArr) || '$0'; }
    get opps() { return (this.stats && this.stats.opps) || '0 / 0'; }
    get loadedLabel() { return (this.stats && this.stats.loaded) || '0 / 0'; }
    get countA() { return (this.stats && this.stats.a) || 0; }
    get countB() { return (this.stats && this.stats.b) || 0; }
    get countC() { return (this.stats && this.stats.c) || 0; }
    get countD() { return (this.stats && this.stats.d) || 0; }
    get mismatches() { return (this.stats && this.stats.mismatches) || 0; }
    get changed() { return (this.stats && this.stats.changed) || 0; }
    get doneToday() { return (this.stats && this.stats.doneToday) || '0 / 0'; }
    get pushedToday() { return (this.stats && this.stats.pushedToday) || '0 / 0'; }
    get chip() { return (this.stats && this.stats.chip) || ''; }
    get chipA() { return this.chip === 'A' ? 'chip on' : 'chip'; }
    get chipB() { return this.chip === 'B' ? 'chip on' : 'chip'; }
    get chipC() { return this.chip === 'C' ? 'chip on' : 'chip'; }
    get chipD() { return this.chip === 'D' ? 'chip on' : 'chip'; }
    get chipM() { return this.chip === 'mismatch' ? 'chip on' : 'chip'; }
    get periodThisNext() { return this.period === 'thisNext'; }
    get periodThis() { return this.period === 'thisQ'; }
    get periodNext() { return this.period === 'nextQ'; }

    emitThreshold(partial) { this.dispatchEvent(new CustomEvent('threshold', { detail: partial })); }
    onPct(e) { this.emitThreshold({ thresholdPct: e.target.value }); }
    onQuota(e) { this.emitThreshold({ quota: e.target.value }); }
    onPeriod(e) { this.emitThreshold({ period: e.target.value }); }
    onGradeRefresh(e) { this.emitThreshold({ gradeOnRefresh: e.target.checked }); }
    onGradeKey() { this.dispatchEvent(new CustomEvent('gradekey')); }
    onGradeSelected() { this.dispatchEvent(new CustomEvent('gradeselected')); }
    onClear() { this.dispatchEvent(new CustomEvent('cleargrades')); }
    onExport() { this.dispatchEvent(new CustomEvent('export')); }
    onChip(e) {
        const k = e.currentTarget.dataset.k;
        if (k) this.dispatchEvent(new CustomEvent('chip', { detail: k }));
    }
}
