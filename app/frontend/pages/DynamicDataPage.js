import React, { useState, useEffect } from "react";
import { Button, Form, Input, Modal, message, Popconfirm ,Upload,Image} from "antd";
import { 
  UploadOutlined, 
  FileOutlined, 
  FilePdfOutlined, 
  FileWordOutlined, 
  FileExcelOutlined 
} from "@ant-design/icons";
import { useParams ,useNavigate} from "react-router";
import { ProTable } from "@ant-design/pro-components";
import { apiFetch } from "@/lib/api/fetch";
const DynamicDataPage = () => {
  const { tableId } = useParams();
  const navigate = useNavigate(); // 用于跳转页面
  const [data, setData] = useState([]);
  const [columns, setColumns] = useState([]);
  const [fields, setFields] = useState([]);
  const [modalVisible, setModalVisible] = useState(false);
  const [editingRecord, setEditingRecord] = useState(null);
  const [form] = Form.useForm();
  const [loading, setLoading] = useState(false);

  const fetchTableData = async (params = {}) => {
    try {
      console.log("Fetching table data...",params);
      const response = await apiFetch(
       `/api/dynamic_tables/${tableId}/dynamic_records?query=${JSON.stringify(params)}`
      );
      // const result = await response.json();

      if (response.fields && response.fields.length > 0) {
        const dynamicColumns = response.fields.map((field) => ({
          title: field.name,
          dataIndex: field.name,
          key: field.name,
          render: (text, record) => {
              // 如果是文件类型，显示预览或下载链接
              if (field.field_type === 'file' && text) {
                // 从 URL 中提取文件名和扩展名
                const urlParts = text.split('/');
                const fileName = urlParts[urlParts.length - 1]; // 获取 URL 最后的部分作为文件名
                const fileExt = fileName.split('.').pop().toLowerCase(); // 提取扩展名
                
                // 根据文件扩展名判断文件类型
                const isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'].includes(fileExt);
                
                if (isImage) {
                  return (
                    <Image 
                      src={text} 
                      alt={field.name}
                      width={50}
                      height={50}
                      style={{ objectFit: 'cover' }}
                      preview={{ src: text }}
                    />
                  );
                } else {
                  // 非图片文件，根据扩展名显示对应图标
                  const fileIcon = getFileIconByExt(fileExt);
                  return (
                    <a 
                      href={`${text}?disposition=attachment`} 
                      target="_blank" 
                      rel="noopener noreferrer"
                    >
                      {fileIcon} {fileName}
                    </a>
                  );
                }
              }
              // 其他类型字段正常显示
              return text;
          },
        }));
        dynamicColumns.push(
          { title: "创建时间", dataIndex: "created_at", key: "created_at" },
          { title: "更新时间", dataIndex: "updated_at", key: "updated_at" },
          {
            title: "操作",
            key: "action",
            render: (_, record) => (
              <>
                <Button
                  type="link"
                  onClick={() => handleEdit(record)}
                >
                  编辑
                </Button>
                <Popconfirm
                  title="确定删除这条记录吗？"
                  onConfirm={() => handleDelete(record.id)}
                >
                  <Button type="link" danger>
                    删除
                  </Button>
                </Popconfirm>
              </>
            ),
          }
        );
        setColumns(dynamicColumns);
        setFields(response.fields);
      }
      console.log(response)
      setData(response.data || []);
    } catch (err) {
      message.error("获取表数据失败");
    }
  };

  const getFileIconByExt = (fileExt) => {
    if (!fileExt) return <FileOutlined style={{ fontSize: '24px' }} />;
    
    // 根据文件扩展名返回对应图标
    switch(fileExt) {
      case 'pdf':
        return <FilePdfOutlined style={{ fontSize: '24px', color: '#ff4d4f' }} />;
      case 'doc':
      case 'docx':
        return <FileWordOutlined style={{ fontSize: '24px', color: '#1890ff' }} />;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return <FileExcelOutlined style={{ fontSize: '24px', color: '#52c41a' }} />;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
      case 'svg':
        return <FileOutlined style={{ fontSize: '24px', color: '#722ed1' }} />;
      default:
        return <FileOutlined style={{ fontSize: '24px' }} />;
    }
  };

  const handleSaveData = async (values) => {
    try {
      setLoading(true);
      const method = editingRecord ? "PUT" : "POST";
      const url = editingRecord
        ? `/api/dynamic_tables/${tableId}/dynamic_records/${editingRecord.id}`
        : `/api/dynamic_tables/${tableId}/dynamic_records`;
  
      const formData = new FormData();
      
      // 处理普通字段
      Object.keys(values).forEach((key) => {
        if (!key.endsWith("_file") && values[key] !== undefined && values[key] !== null) {
          formData.append(`record[${key}]`, values[key]);
        }
      });
      formData.append("dynamic_table_id", tableId);
      
      // 特殊处理文件字段（仅当存在文件字段时）
      if (fields && fields.some((field) => field.field_type === "file")) {
        fields.forEach((field) => {
          if (field.field_type === "file") {
            const fileKey = `${field.name}_file`;
            const fileList = values[fileKey];

            if (fileList && fileList.length > 0 && fileList[0].originFileObj) {
              // 直接将文件对象添加到 FormData
              formData.append(`record[${field.name}]`, fileList[0].originFileObj);
            }
          }
        });
      }
  
      // 设置请求选项
      const requestOptions = {
        method,
        body: formData,
      };
  
      const response = await apiFetch(url, requestOptions);
      console.log("Response:", response);
      if (response.ok) {
        message.success(editingRecord ? "数据更新成功" : "数据保存成功");
        setModalVisible(false);
        setEditingRecord(null);
        form.resetFields();
        fetchTableData();
      } else {
        const errorData = await response.json();
        message.error(errorData.error || (editingRecord ? "数据更新失败" : "数据保存失败"));
      }
    } catch (err) {
      console.error("保存数据错误:", err);
      message.error(editingRecord ? "数据更新失败" : "数据保存失败");
    }
    finally{
      setLoading(false);
    }
  };

  const handleDelete = async (id) => {
    try {
      const response = await apiFetch(
        `/api/dynamic_tables/${tableId}/dynamic_records/${id}`,
        { method: "DELETE" }
      );

      if (response.ok) {
        message.success("数据删除成功");
        fetchTableData();
      } else {
        message.error("数据删除失败");
      }
    } catch (err) {
      message.error("数据删除失败");
    }
  };

  const handleEdit = (record) => {
    setEditingRecord(record);
    
    // 创建一个新的表单值对象
    const formValues = { ...record };
    
    // 处理文件字段
    fields.forEach(field => {
      if (field.field_type === 'file' && record[field.name]) {
        // 如果有文件字段，设置一个空的 fileList
        // 实际文件会在其他地方处理（例如显示预览或下载链接）
        formValues[`${field.name}_file`] = [];
      }
    });
    
    form.setFieldsValue(formValues);
    setModalVisible(true);
  };

  const renderFormItems = () => {
    return fields.map((field) => {
      let inputComponent;
      switch (field.field_type) {
        case "file":
          inputComponent = (
            <>
              <Form.Item
                noStyle
                name={`${field.name}_file`}
                valuePropName="fileList"
                getValueFromEvent={e => {
                  if (Array.isArray(e)) {
                    return e;
                  }
                  return e?.fileList;
                }}
              >
                <Upload
                  beforeUpload={() => false}
                  maxCount={1}
                  listType="picture"
                  accept="image/*,.pdf,.doc,.docx,.xls,.xlsx"
                >
                  <Button icon={<UploadOutlined />}>上传文件</Button>
                </Upload>
              </Form.Item>
              
              {/* 显示已上传的文件 */}
              {editingRecord && editingRecord[field.name] && (
                <div style={{ marginTop: 8 }}>
                  {/\.(jpg|jpeg|png|gif|webp)$/i.test(editingRecord[field.name]) ? (
                    // 图片预览
                    <div>
                      <p>已上传图片：</p>
                      <Image 
                        src={`${editingRecord[field.name]}`} 
                        alt="已上传图片"
                        width={100}
                        style={{ objectFit: 'cover' }}
                      />
                    </div>
                  ) : (
                    // 文件下载链接
                    <a 
                      href={`${editingRecord[field.name]}`} 
                      target="_blank" 
                      rel="noopener noreferrer"
                    >
                      查看已上传文件
                    </a>
                  )}
                </div>
              )}
            </>
          );
          break;
        case "integer":
          inputComponent = <Input type="number" placeholder={`请输入 ${field.name}`} />;
          break;
        case "boolean":
          inputComponent = <Input type="checkbox" style={{ width: "auto" }} />;
          break;
        case "date":
          inputComponent = <Input type="date" />;
          break;
        case "datetime":
          inputComponent = <Input type="datetime-local" />;
          break;
        case "decimal":
        case "float":
          inputComponent = <Input type="number" step="0.01" />;
          break;
        default:
          inputComponent = <Input />;
      }

      const rules = [];
      if (field.required) {
        rules.push({ required: true, message: `${field.name} 是必填项` });
      }

      return (
        <Form.Item key={field.name} label={field.name} name={field.name} rules={rules}>
          {inputComponent}
        </Form.Item>
      );
    });
  };
  const handleCreateFields = () => {
    // 跳转到字段创建页面
    navigate(`/admin/dynamic_fields/${tableId}`);
  };
  useEffect(() => {
  fetchTableData();
  }, [tableId]); // <--- 空数组是关键！
  return (
    <div>
        {fields.length === 0 ? (
        <div style={{ textAlign: "center", marginTop: "20px" }}>
          <p>当前表格尚未创建字段，请先创建字段。</p>
          <Button type="primary" onClick={handleCreateFields}>
            去创建字段
          </Button>
        </div>
      ) : (
        <>
          <ProTable
            rowKey="id"
            columns={columns}
            dataSource={data}
            pagination={{ pageSize: 10 }}
            search={true}
            toolBarRender={() => [
              <Button
                key="add"
                type="primary"
                onClick={() => {
                  setEditingRecord(null);
                  form.resetFields();
                  setModalVisible(true);
                }}
              >
                新增数据
              </Button>,
            ]}
            request={async (params) => {
              await fetchTableData(params);
              return { data, success: true };
            }}
          />
          <Modal
            title={editingRecord ? "编辑数据" : "新增数据"}
            open={modalVisible}
            onCancel={() => setModalVisible(false)}
            footer={[
              <Button key="cancel" onClick={() => setModalVisible(false)}>
                取消
              </Button>,
              <Button
                key="submit"
                type="primary"
                loading={loading}
                onClick={() => {
                  form.validateFields().then((values) => {
                    handleSaveData(values);
                  });
                }}
              >
                保存
              </Button>,
            ]}
          >
            <Form form={form} layout="vertical">
              {renderFormItems()}
            </Form>
          </Modal>
        </>
      )}
    </div>
  );
};

export default DynamicDataPage;