import { LightningElement, wire } from 'lwc';
import getDirectorOpportunities from '@salesforce/apex/TeamOpportunityController.getDirectorOpportunities';
import summarizeOpportunity from '@salesforce/apex/TeamOpportunityController.summarizeOpportunity';

const COLUMNS = [
    { label: 'Opportunity', fieldName: 'name', type: 'text' },
    { label: 'Account', fieldName: 'accountName', type: 'text' },
    { label: 'Stage', fieldName: 'stageName', type: 'text' },
    { label: 'Amount', fieldName: 'amount', type: 'currency' },
    { label: 'Close Date', fieldName: 'closeDate', type: 'date-local' },
    { label: 'Owner', fieldName: 'ownerName', type: 'text' },
    {
        type: 'button',
        typeAttributes: {
            label: 'Tell me about this opportunity',
            name: 'summarize',
            variant: 'brand'
        }
    }
];

export default class TeamOpportunityInsights extends LightningElement {
    columns = COLUMNS;
    opportunities = [];
    error;
    loadingList = true;
    summarizing = false;
    summaryText;
    selectedName;

    @wire(getDirectorOpportunities)
    wiredOpps({ data, error }) {
        this.loadingList = false;
        if (data) {
            this.opportunities = data;
            this.error = undefined;
        } else if (error) {
            this.error = this.reduceError(error);
        }
    }

    handleRowAction(event) {
        const row = event.detail.row;
        this.selectedName = row.name;
        this.summaryText = undefined;
        this.error = undefined;
        this.summarizing = true;
        summarizeOpportunity({ opportunityId: row.id })
            .then((result) => {
                this.summaryText = result;
            })
            .catch((err) => {
                this.summaryText = undefined;
                this.error = this.reduceError(err);
            })
            .finally(() => {
                this.summarizing = false;
            });
    }

    get hasOpportunities() {
        return this.opportunities && this.opportunities.length > 0;
    }

    get noOpportunities() {
        return !this.loadingList && !this.hasOpportunities && !this.error;
    }

    reduceError(error) {
        if (Array.isArray(error && error.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return (error && error.message) || 'Unknown error';
    }
}
