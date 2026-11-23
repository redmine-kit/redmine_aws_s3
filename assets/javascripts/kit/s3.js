// Redmine Kit AWS S3: the plugin's module for the new UI, built from frontend/src by `npm run build` (frontend/vite.config.js).
// Edit the source, not this file. React, @redmine-kit/ui and @redmine-kit/plugin come from the app (the shell's import map).
import { useState } from "react";
import { AttrGrid, AttrGridSkeleton, Button, CardBody, CardSection, DataTable, EmptyState, FormActions, FormRow, Icon, Input, ListRow, Notice, RequestErrorState, SectionHeading, SkeletonRegion, useFormDirty } from "@redmine-kit/ui";
import { AppLink, useApiErrorTexts, useKitMutation, useKitQuery, useT } from "@redmine-kit/plugin";
import { Fragment, jsx, jsxs } from "react/jsx-runtime";
// src/api.ts
var s3Paths = {
	/** GET: the tab; PATCH { settings }: saves the settings */
	admin: "/admin/aws/s3.json",
	/** POST: the read/write check */
	readWrite: "/admin/aws/s3/read_write.json",
	/** POST: the delivery check */
	delivery: "/admin/aws/s3/delivery.json",
	/** POST: starts the consistency check */
	reconcile: "/admin/aws/s3/reconcile.json"
};
/** The settings in the page's order, each with its unit. */
var SETTINGS = [
	{
		name: "download_url_expiry",
		unit: "seconds"
	},
	{
		name: "upload_url_expiry",
		unit: "seconds"
	},
	{
		name: "cache_size_mb",
		unit: "MB"
	}
];
// src/AwsS3Admin.tsx
/** Redmine's .tabular labels (175px), as the classic page's values line up. */
var LABEL_WIDTH = 175;
/**
* A value with its note muted under it, as Redmine's em.info under a value (the variable a value comes from); a long
* value (a bucket's or a domain's name) wraps anywhere rather than being cut.
*/
function NotedValue({ value, note }) {
	return /* @__PURE__ */ jsxs("span", {
		className: "flex min-w-0 flex-col whitespace-normal wrap-anywhere",
		children: [/* @__PURE__ */ jsx("span", { children: value }), note && /* @__PURE__ */ jsx("span", {
			className: "text-meta text-text-muted",
			children: note
		})]
	});
}
/** Values as label and value pairs, each note muted under its value (the classic page's em.info). */
function Values({ rows }) {
	return /* @__PURE__ */ jsx("div", {
		className: "px-gutter",
		children: /* @__PURE__ */ jsx(AttrGrid, {
			columns: 1,
			labelWidth: LABEL_WIDTH,
			items: rows.map((row) => ({
				label: row.name,
				value: /* @__PURE__ */ jsx(NotedValue, {
					value: row.value ?? "",
					note: row.note
				})
			}))
		})
	});
}
function AwsS3Admin() {
	const t = useT();
	const query = useKitQuery(s3Paths.admin);
	const action = useKitMutation();
	const errorTexts = useApiErrorTexts();
	const [result, setResult] = useState(null);
	const run = (path) => {
		setResult(null);
		action.mutate({
			method: "post",
			path,
			body: {}
		}, { onSuccess: (data) => setResult(data ?? null) });
	};
	if (query.isError) return /* @__PURE__ */ jsx(CardBody, { children: /* @__PURE__ */ jsx(RequestErrorState, {
		error: query.error,
		onRetry: () => void query.refetch(),
		retrying: query.isFetching
	}) });
	const data = query.data;
	const errors = errorTexts(action.error);
	const findingColumns = [
		{
			key: "time",
			label: t("label_aws_s3_time"),
			type: "text",
			value: (r) => r.finding.time
		},
		{
			key: "result",
			label: t("label_aws_s3_scan_result"),
			type: "text",
			value: (r) => r.finding.result
		},
		{
			key: "filename",
			label: t("field_filename"),
			type: "text",
			value: (r) => r.finding.filename
		},
		{
			key: "user",
			label: t("label_user"),
			type: "text",
			value: (r) => r.finding.user?.name ?? r.finding.login ?? "",
			cell: (r) => r.finding.user ? /* @__PURE__ */ jsx(AppLink, {
				href: `/users/${r.finding.user.id}`,
				children: r.finding.user.name
			}) : r.finding.login ?? ""
		}
	];
	if (!data) return /* @__PURE__ */ jsx(CardBody, { children: /* @__PURE__ */ jsx(CardSection, {
		line: false,
		heading: t("label_aws_s3_environment"),
		children: /* @__PURE__ */ jsx(SkeletonRegion, {
			label: t("label_loading"),
			className: "px-gutter",
			children: /* @__PURE__ */ jsx(AttrGridSkeleton, {
				columns: 1,
				labelWidth: LABEL_WIDTH,
				items: [
					"bucket",
					"region",
					"domain",
					"key_pair_id",
					"private_key",
					"malware_scan",
					"storage_path"
				].map((name) => ({ label: t(`field_aws_s3_${name}`) }))
			})
		})
	}) });
	return /* @__PURE__ */ jsxs(CardBody, { children: [
		!data.enabled && /* @__PURE__ */ jsx(Notice, {
			tone: "warning",
			text: t("text_aws_s3_off", { name: data.bucket_variable }),
			wrap: true
		}),
		result?.notice && /* @__PURE__ */ jsx(Notice, {
			tone: "neutral",
			text: result.notice
		}),
		errors.length > 0 && /* @__PURE__ */ jsx(Notice, {
			tone: "danger",
			role: "alert",
			text: errors.join("\n"),
			wrap: true
		}),
		/* @__PURE__ */ jsx(CardSection, {
			line: false,
			heading: t("label_aws_s3_environment"),
			children: /* @__PURE__ */ jsx(Values, { rows: data.environment })
		}),
		data.enabled && /* @__PURE__ */ jsxs(Fragment, { children: [
			/* @__PURE__ */ jsxs(CardSection, {
				heading: t("label_aws_s3_checks"),
				children: [/* @__PURE__ */ jsxs("div", {
					className: "mb-3 flex flex-wrap items-center gap-2 px-gutter",
					children: [/* @__PURE__ */ jsx(Button, {
						size: 28,
						disabled: action.isPending,
						onClick: () => run(s3Paths.readWrite),
						children: t("button_aws_s3_read_write")
					}), /* @__PURE__ */ jsx(Button, {
						size: 28,
						disabled: action.isPending,
						onClick: () => run(s3Paths.delivery),
						children: t("button_aws_s3_delivery")
					})]
				}), result?.results?.map((row, i, rows) => /* @__PURE__ */ jsx(ListRow, {
					title: row.name,
					sub: row.value || void 0,
					divider: i < rows.length - 1,
					cols: [{ content: /* @__PURE__ */ jsx("span", {
						className: row.ok ? "flex text-accent" : "flex text-warning",
						role: "img",
						"aria-label": row.ok ? t("label_aws_ok") : t("label_aws_failed"),
						children: /* @__PURE__ */ jsx(Icon, {
							name: row.ok ? "check" : "warning",
							size: 16
						})
					}) }]
				}, `${row.name}-${i}`))]
			}),
			data.findings && /* @__PURE__ */ jsx(CardSection, {
				heading: t("label_aws_s3_malware_findings"),
				children: data.findings.length === 0 ? /* @__PURE__ */ jsx(EmptyState, {}) : /* @__PURE__ */ jsx(DataTable, {
					label: t("label_aws_s3_malware_findings"),
					columns: findingColumns,
					rows: data.findings.map((finding, i) => ({
						id: String(i),
						finding
					}))
				})
			}),
			/* @__PURE__ */ jsx(CardSection, {
				heading: t("label_aws_s3_reconciliation"),
				actions: /* @__PURE__ */ jsx(Button, {
					size: 28,
					disabled: action.isPending,
					onClick: () => run(s3Paths.reconcile),
					children: t("button_aws_s3_reconcile")
				}),
				children: !data.reconciliation ? /* @__PURE__ */ jsx(EmptyState, {}) : /* @__PURE__ */ jsxs("div", {
					className: "flex flex-col gap-3",
					children: [/* @__PURE__ */ jsx(Values, { rows: data.reconciliation.rows }), ["missing", "unused"].map((kind) => data.reconciliation[kind].length > 0 ? /* @__PURE__ */ jsxs("div", { children: [/* @__PURE__ */ jsx(SectionHeading, {
						heading: t(`field_aws_s3_${kind}`),
						level: 3,
						inset: 24,
						count: data.reconciliation[kind].length
					}), data.reconciliation[kind].map((key) => /* @__PURE__ */ jsx(ListRow, {
						title: key,
						mono: true,
						size: 32
					}, key))] }, kind) : null)]
				})
			})
		] }),
		/* @__PURE__ */ jsx(CardSection, {
			heading: t("label_settings"),
			children: /* @__PURE__ */ jsx(SettingsForm, { settings: data.settings }, JSON.stringify(data.settings))
		})
	] });
}
/** 設定: the plugin's settings as the page's form has them, with their units; 保存 saves them (PATCH { settings }). */
function SettingsForm({ settings }) {
	const t = useT();
	const save = useKitMutation(s3Paths.admin, "patch");
	const errorTexts = useApiErrorTexts();
	const [values, setValues] = useState(settings);
	const form = useFormDirty(values);
	const errors = errorTexts(save.error);
	return /* @__PURE__ */ jsxs(Fragment, { children: [
		save.isSuccess && !form.dirty && /* @__PURE__ */ jsx(Notice, {
			tone: "neutral",
			role: "status",
			text: t("notice_successful_update")
		}),
		errors.length > 0 && /* @__PURE__ */ jsx(Notice, {
			tone: "danger",
			role: "alert",
			text: errors.join("\n"),
			wrap: true
		}),
		/* @__PURE__ */ jsx("div", {
			className: "box-content flex max-w-215 flex-col gap-4 px-6",
			children: SETTINGS.map(({ name, unit }) => /* @__PURE__ */ jsx(FormRow, {
				label: t(`field_aws_s3_${name}`),
				children: /* @__PURE__ */ jsxs("span", {
					className: "flex items-center gap-2",
					children: [/* @__PURE__ */ jsx(Input, {
						"aria-label": t(`field_aws_s3_${name}`),
						inputMode: "numeric",
						value: values[name] ?? "",
						onChange: (e) => setValues({
							...values,
							[name]: e.target.value
						}),
						className: "w-24"
					}), unit && /* @__PURE__ */ jsx("span", { children: unit === "seconds" ? t("label_aws_s3_seconds") : "MB" })]
				})
			}, name))
		}),
		/* @__PURE__ */ jsxs(FormActions, { children: [/* @__PURE__ */ jsx(Button, {
			"data-form-cancel": true,
			variant: "ghost",
			disabled: !form.dirty || save.isPending,
			onClick: () => setValues(form.saved),
			children: t("button_cancel")
		}), /* @__PURE__ */ jsx(Button, {
			submit: "primary",
			variant: "primary",
			disabled: !form.dirty || save.isPending,
			onClick: () => save.mutate({ settings: values }, { onSuccess: () => form.markSaved() }),
			children: t("button_save")
		})] })
	] });
}
export { AwsS3Admin };
