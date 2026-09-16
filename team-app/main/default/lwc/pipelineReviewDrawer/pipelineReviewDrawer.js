import { LightningElement, api } from 'lwc';
export default class PipelineReviewDrawer extends LightningElement {
    @api row;
    @api preview;
    @api error;
    note = '';
    renderedCallback() {
        if (this.row && !this.note) this.note = this.row.note || '';
    }
    onNote(e) { this.note = e.target.value; }
    onSave() { this.dispatchEvent(new CustomEvent('savenote', { detail: { id: this.row.id, note: this.note } })); }
    onRegen() { this.dispatchEvent(new CustomEvent('regenone', { detail: this.row.id })); }
    onClose() { this.dispatchEvent(new CustomEvent('close')); }
}
