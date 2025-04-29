import React from 'react';
import { EditableProTable } from '@ant-design/pro-components';

const FieldEditor = ({ fields, setFields, editableKeys, setEditableRowKeys }) => {
  const fieldTypeOptions = {
    string: { text: "字符串" },
    integer: { text: "整数" },
    boolean: { text: "布尔值" },
    text: { text: "长文本" },
    date: { text: "日期" },
    datetime: { text: "日期时间" },
    decimal: { text: "小数" },
    float: { text: "浮点数" },
  };
  const columns = [
    {
      title: '字段名称',
      dataIndex: 'name',
      editable: true,
      formItemProps: {
        rules: [{ required: true, message: '字段名称不能为空' }],
      },
    },
    {
      title: '字段类型',
      dataIndex: 'field_type',
      valueType: 'select',
      valueEnum: fieldTypeOptions,
      editable: true,
      formItemProps: {
        rules: [{ required: true, message: '字段类型不能为空' }],
      },
    },
    {
      title: '是否必填',
      dataIndex: 'required',
      valueType: 'switch',
      render: (text, record) => (record.required ? '是' : '否'),
      editable: true,
    },
    {
      title: '操作',
      valueType: 'option',
      render: (text, record, _, action) => [
        <a
          key="editable"
          onClick={() => {
            action?.startEditable?.(record.id);
          }}
        >
          编辑
        </a>,
        <a
          key="delete"
          onClick={() => {
            setFields(fields.filter((item) => item.id !== record.id));
          }}
        >
          删除
        </a>,
      ],
    },
  ];

  return (
    <EditableProTable
      rowKey="id"
      headerTitle="字段列表"
      value={fields}
      onChange={setFields}
      columns={columns}
      editable={{
        type: 'multiple',
        editableKeys,
        onChange: setEditableRowKeys,
      }}
      recordCreatorProps={{
        position: 'bottom',
        record: () => ({
          id: Date.now(), // 使用时间戳作为临时 ID
          name: '',
          field_type: 'string', // 默认字段类型
          isNew: true, // 新增字段标记
          required: false, // 默认值为非必填
        }),
      }}
    />
  );
};

export default FieldEditor;