import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getReviewDeals from '@salesforce/apex/PricingReviewController.getReviewDeals';
import createReview from '@salesforce/apex/PricingReviewController.createReview';

const QUESTIONS = [
    'Total Budget and Operating Budget, Population/Student Count + Employees',
    'Where did this Opportunity come from?',
    'Do they have an Euna product currently? What? When purchased? Current ARR?',
    'How partial has the prospect been to our solution thus far?',
    'Who are we competing against and where do we expect them to be on pricing?',
    'Who are comparable customers and what have we priced them at?',
    'Does the prospect have budget for this project? How much?',
    'How much weight is being placed on pricing in the evaluation?',
    'Have we already communicated a previous quote or ballpark pricing?',
    'Any timing pressure on delivery of a pricing quote?',
    'Is this pricing based on: Budgetary / Direct Purchase / State Contract / RFP?',
    'What is their purchasing process? Open to cooperative purchasing vehicles?',
    'Is there an opportunity for a time-based incentive to drive a decision?',
    'Over what period is the prospect evaluating TCO? 3 years or less? 5 or more?',
    'What is more important: minimizing Year 1 cost or minimizing ongoing SaaS costs?',
    'What are the main drivers behind their decision to purchase?',
    'What differentiates Euna from our competition?',
    'How many users need access to the software?',
    'Is the target execution date known?',
    'Has a SE or IM reviewed or scoped this?',
    'What Sales Options have been included?',
    'What non-standard items have been requested?',
    'When does implementation need to be completed by?',
    'What are your recommendations on Pricing and Term?'
];
const BATCHES = [
    { label: 'Batch 1 \u2014 Deal Context', from: 1, to: 5 },
    { label: 'Batch 2 \u2014 Competitive', from: 6, to: 10 },
    { label: 'Batch 3 \u2014 Process', from: 11, to: 15 },
    { label: 'Batch 4 \u2014 Deal Shape', from: 16, to: 20 },
    { label: 'Batch 5 \u2014 Scope & Recommendation', from: 21, to: 24 }
];

export default class PricingReviewTool extends LightningElement {
    wired;
    rows = [];
    error;
    selected;
    saving = false;
    done;
    answers = {};

    @wire(getReviewDeals)
    w(result) {
        this.wired = result;
        if (result.data) {
            this.rows = result.data.map((d) => ({
                id: d.id, account: d.account, ae: d.ae, stage: d.stage, leadSource: d.leadSource,
                arrFmt: this.money(d.arr), closeDate: d.closeDate, done: d.reviewDone,
                statusPill: 'pill ' + (d.reviewDone ? 'p-hi' : 'p-ex'),
                statusLabel: d.reviewDone ? 'Done' : 'Not done'
            }));
            this.error = undefined;
        } else if (result.error) { this.error = this.msg(result.error); }
    }

    money(n) { return n == null ? '\u2014' : '$' + Math.round(n).toLocaleString('en-US'); }
    msg(e) { return (e && e.body && e.body.message) || 'Something went wrong.'; }
    get hasRows() { return this.rows.length > 0; }
    get openCount() { return this.rows.length; }
    get doneCount() { return this.rows.filter((r) => r.done).length; }

    get questionGroups() {
        return BATCHES.map((b) => {
            const items = [];
            for (let n = b.from; n <= b.to; n++) {
                const key = 'Q' + n;
                items.push({ key, num: n, label: QUESTIONS[n - 1], value: this.answers[key] || '' });
            }
            return { label: b.label, items };
        });
    }

    pick(e) {
        const id = e.currentTarget.dataset.id;
        this.selected = this.rows.find((x) => x.id === id);
        this.done = undefined; this.error = undefined;
        // pre-fill Q2 (lead source) from Salesforce, per the skill
        this.answers = this.selected && this.selected.leadSource ? { Q2: this.selected.leadSource } : {};
    }
    cancel() { this.selected = undefined; }
    setAnswer(e) { this.answers = { ...this.answers, [e.target.dataset.q]: e.target.value }; }

    create() {
        this.saving = true; this.done = undefined; this.error = undefined;
        createReview({ opportunityId: this.selected.id, answers: this.answers })
            .then(() => { this.done = 'Euna Pricing Review Checklist generated and attached to the opportunity Files.'; this.selected = undefined; return refreshApex(this.wired); })
            .catch((err) => { this.error = this.msg(err); })
            .finally(() => { this.saving = false; });
    }
}
