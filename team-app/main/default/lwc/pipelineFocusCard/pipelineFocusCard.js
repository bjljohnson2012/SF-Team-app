import { LightningElement, api } from 'lwc';
export default class PipelineFocusCard extends LightningElement {
    @api row;
    showBreak = false;
    get score() { return this.row && this.row.priority != null ? Math.round(this.row.priority) : '—'; }
    get arr() { return this.row && this.row.arr != null ? '$' + Math.round(this.row.arr).toLocaleString() : ''; }
    get mailto() { return this.row && this.row.contactEmail ? 'mailto:' + this.row.contactEmail : '#'; }
    get isSuggestion() {
        return this.row && (!this.row.nextStep || this.row.nextStepState === 'Missing' || this.row.nextStepState === 'PastDue')
            && this.row.suggestedNextStep;
    }
    onScore() { this.showBreak = !this.showBreak; }
    onDone() { this.dispatchEvent(new CustomEvent('done', { detail: this.row })); }
    onResched() { this.dispatchEvent(new CustomEvent('reschedule', { detail: this.row })); }
    onSnooze() { this.dispatchEvent(new CustomEvent('snooze', { detail: this.row })); }
    onAccept() { this.dispatchEvent(new CustomEvent('accept', { detail: this.row })); }
}
