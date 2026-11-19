export const reviewLabels = {
 todo: "Att göra",
 in_progress: "Pågår",
 reviewed: "Granskad",
};

export type RowReview = {
 fingerprint: string;
 revision: number;
 note: string | null;
 updated_at: string | null;
 review_state: keyof typeof reviewLabels;
 changed_since_review: boolean;
};
