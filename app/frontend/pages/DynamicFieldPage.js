import React, { useState, useEffect } from 'react';
import { Button, Form, Checkbox, Modal, message } from 'antd';
import {
    EditableProTable,
    ProCard,
    ProFormField,
    ProFormRadio,
  } from '@ant-design/pro-components';
import { apiFetch } from '@/lib/api/fetch';
import { useParams } from "react-router";
import FieldEditor from '@/components/FieldEditor';

const DynamicFieldPage = () => {
    const { tableId } = useParams(); // 获取 URL 参数中的 tableId
    const [fields, setFields] = useState([]); // 字段数据
    const [editableKeys, setEditableRowKeys] = useState([]); // 可编辑行的 key
    const [tableName, setTableName] = useState(""); // 表格名称
  useEffect(() => {
    const fetchFields = async () => {
      try {
        const response = await apiFetch(`/api/dynamic_tables/${tableId}/dynamic_fields`);
        setFields(response.fields);
        setTableName(response.table_name)
      } catch (err) {
        message.error('获取字段失败');
      }
    };
    fetchFields();
  }, [tableId]);

  const handleSaveFields = async () => {
    try {
    const processedFields = fields.map((field) => {
        const { isNew, ...rest } = field; // 移除 isNew 字段
        if (isNew) {
          rest.id = null; // 新字段的 ID 设置为 null
        }
        return rest;
        });
      await apiFetch(`/api/dynamic_tables/${tableId}/dynamic_fields`, {
        headers:{"Content-Type": "application/json"},
        method: 'POST',
        body: JSON.stringify({dynamic_table_id:tableId, fields:processedFields }),
      });
      message.success('字段更新成功');
    } catch (err) {
      message.error('字段更新失败');
    }
  };

    // 表格列定义
    const columns = [
        {
          title: "字段名称",
          dataIndex: "name",
          editable: true,
          formItemProps: {
            rules: [{ required: true, message: "字段名称不能为空" }],
          },
        },
        {
          title: "字段类型",
          dataIndex: "field_type",
          valueType: "select",
          valueEnum: {
            string: { text: "字符串" },
            integer: { text: "整数" },
            boolean: { text: "布尔值" },
            date: { text: "日期" },
          },
          editable: true,
          formItemProps: {
            rules: [{ required: true, message: "字段类型不能为空" }],
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
          title: "操作",
          valueType: "option",
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
        <div>
          <h1>{tableName}</h1>
          <FieldEditor
                fields={fields}
                setFields={setFields}
                editableKeys={editableKeys}
                setEditableRowKeys={setEditableRowKeys}
        />
          <Button type="primary" onClick={handleSaveFields} style={{ marginTop: 16 }}>
            保存字段
          </Button>
        </div>
      );
};

export default DynamicFieldPage;
