import { LightningElement, api } from 'lwc';
export default class PipelineReviewSavedViews extends LightningElement {
    @api views = [];
    @api changedOnly = false;
    selectedId;
    onPick(e) {
        this.selectedId = e.target.value;
        const v = (this.views || []).find((x) => x.id === this.selectedId);
        if (v) this.dispatchEvent(new CustomEvent('viewload', { detail: v }));
    }
    onSave() { this.dispatchEvent(new CustomEvent('viewsave')); }
    onDel() { this.dispatchEvent(new CustomEvent('viewdel', { detail: this.selectedId })); }
    onReset() { this.dispatchEvent(new CustomEvent('viewreset')); }
    onRefresh() { this.dispatchEvent(new CustomEvent('viewrefresh')); }
    onChanged(e) { this.dispatchEvent(new CustomEvent('changedonly', { detail: e.target.checked })); }
}
