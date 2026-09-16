import { LightningElement, api } from 'lwc';
export default class PipelineReviewRow extends LightningElement {
    @api row;
    @api selected = false;
    get arr() { return this.row && this.row.arr != null ? '$' + Math.round(this.row.arr).toLocaleString() : '—'; }
    get gradeClass() { return 'pill p-' + String(this.row && this.row.grade ? this.row.grade : 'd').toLowerCase(); }
    get mismatchClass() { return this.row && this.row.mismatch ? 'mismatch' : ''; }
    get rowClass() { return this.selected ? 'selected' : ''; }
    get tagA() { return this.row && this.row.tag === 'A'; }
    get tagB() { return this.row && this.row.tag === 'B'; }
    get tagC() { return this.row && this.row.tag === 'C'; }
    get tagD() { return this.row && this.row.tag === 'D'; }
    onPick(e) {
        e.stopPropagation();
        this.dispatchEvent(new CustomEvent('pick', { detail: { id: this.row.id, selected: e.target.checked } }));
    }
    onTag(e) {
        e.stopPropagation();
        this.dispatchEvent(new CustomEvent('tag', { detail: { id: this.row.id, tag: e.target.value } }));
    }
    onOpen() { this.dispatchEvent(new CustomEvent('open', { detail: this.row })); }
}
