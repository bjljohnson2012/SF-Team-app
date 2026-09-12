import { LightningElement } from 'lwc';

const TOOLS = [
    {
        id: 'pricing',
        name: 'Pricing Review Checklist',
        desc: 'Run a pricing review on an open deal. Claude pre-fills the 24 questions from the opportunity\u2019s data, then generates a branded Euna Word document into the opportunity\u2019s Files.',
        tag: 'New-business deals \u2265 $30K ARR',
        icon: 'standard:pricebook'
    }
];

export default class SalesTools extends LightningElement {
    selected;

    get tools() { return TOOLS; }
    get showGrid() { return !this.selected; }
    get isPricing() { return this.selected === 'pricing'; }

    open(e) { this.selected = e.currentTarget.dataset.id; }
    back() { this.selected = undefined; }
}
