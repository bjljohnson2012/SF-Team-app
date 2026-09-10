import { LightningElement, wire } from 'lwc';
import load from '@salesforce/apex/CockpitForecastController.load';

const COLUMNS = [
    { label: 'Account', fieldName: 'account', type: 'text', wrapText: true },
    { label: 'AE', fieldName: 'ae', type: 'text' },
    { label: 'Stage', fieldName: 'stage', type: 'text' },
    { label: 'ARR', fieldName: 'arr', type: 'currency',
      typeAttributes: { maximumFractionDigits: 0 }, cellAttributes: { alignment: 'right' } },
    { label: 'Close', fieldName: 'closeDate', type: 'date-local' },
    { label: 'Score', fieldName: 'score', type: 'number', cellAttributes: { alignment: 'left' },
      initialWidth: 80 },
    { label: 'Class', fieldName: 'klass', type: 'text', initialWidth: 80 },
    { label: 'Pushes', fieldName: 'pushes', type: 'number', cellAttributes: { alignment: 'left' },
      initialWidth: 90 },
    { label: 'Signal trace', fieldName: 'reason', type: 'text', wrapText: true }
];

export default class ForecastHub extends LightningElement {
    columns = COLUMNS;
    data;
    error;
    loading = true;
    teamSize;
    dealCount = 0;
    highArr;
    modeledCall;
    quarterLabel;

    @wire(load)
    handle({ data, error }) {
        this.loading = false;
        if (data) {
            this.data = data.deals;
            this.teamSize = data.teamSize;
            this.dealCount = data.deals.length;
            this.highArr = data.highArr;
            this.modeledCall = data.modeledCall;
            this.quarterLabel = data.quarterLabel;
            this.error = undefined;
        } else if (error) {
            this.error = (error.body && error.body.message) || 'Could not load the Forecasting Hub.';
        }
    }

    get hasData() {
        return this.data && this.data.length > 0;
    }

    get noData() {
        return !this.loading && !this.error && (!this.data || this.data.length === 0);
    }
}
