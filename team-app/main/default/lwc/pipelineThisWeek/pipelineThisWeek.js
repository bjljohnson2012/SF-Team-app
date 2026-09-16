import { LightningElement } from 'lwc';
import loadThisWeek from '@salesforce/apex/PipelineReviewController.loadThisWeek';
import markDone from '@salesforce/apex/PipelineReviewController.markDone';
import reschedule from '@salesforce/apex/PipelineReviewController.reschedule';
import snooze from '@salesforce/apex/PipelineReviewController.snooze';
import acceptSuggestion from '@salesforce/apex/PipelineReviewController.acceptSuggestion';

const STORE = 'pipelineThisWeekMode';

export default class PipelineThisWeek extends LightningElement {
    loading = true;
    error;
    mode;
    directorId;
    page = { focus: [], dueThisWeek: [], decideOrKill: [], fixFirst: [], aeChips: [], focusCount: 0, dueCount: 0, overdueCount: 0, unworkableCount: 0, cleared: 0 };

    connectedCallback() {
        try { this.mode = sessionStorage.getItem(STORE) || undefined; } catch (e) { this.mode = undefined; }
        this.refresh();
    }
    get isWeek() { return this.page.mode === 'week'; }
    get isToday() { return this.page.mode === 'today'; }
    get hasChips() { return this.page.aeChips && this.page.aeChips.length > 1; }
    get headerLine() {
        const asOf = this.page.lastUpdated ? new Date(this.page.lastUpdated).toLocaleString() : 'grades pending';
        return (this.isWeek ? 'Week of ' + this.page.weekStart : 'Today') + ' · as of ' + asOf;
    }
    refresh() {
        this.loading = true;
        loadThisWeek({ mode: this.mode, directorId: this.directorId })
            .then((p) => { this.page = p; this.mode = p.mode; this.error = undefined; })
            .catch((e) => { this.error = (e.body && e.body.message) || e.message; })
            .finally(() => { this.loading = false; });
    }
    onMode(e) {
        this.mode = e.target.value;
        try { sessionStorage.setItem(STORE, this.mode); } catch (err) { /* ignore */ }
        this.refresh();
    }
    onScope(e) { this.directorId = e.detail.directorId; this.refresh(); }
    onDone(e) {
        const next = window.prompt('Next step', e.detail.suggestedNextStep || '');
        markDone({ opportunityId: e.detail.id, focusId: null, nextStep: next, nextDate: e.detail.suggestedNextStepDate })
            .then(() => this.refresh());
    }
    onResched(e) {
        const d = window.prompt('New next-step date (YYYY-MM-DD)');
        if (!d) return;
        reschedule({ opportunityId: e.detail.id, focusId: null, nextDate: d }).then(() => this.refresh());
    }
    onSnooze(e) {
        const d = window.prompt('Snooze until (YYYY-MM-DD)');
        if (!d) return;
        snooze({ opportunityId: e.detail.id, untilDate: d }).then(() => this.refresh());
    }
    onAccept(e) { acceptSuggestion({ opportunityId: e.detail.id }).then(() => this.refresh()); }
}
