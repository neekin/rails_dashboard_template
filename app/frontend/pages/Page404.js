import React from "react";
import { Button, Result } from "antd";
import { useNavigate } from "react-router";

const Page404 = () => {
  const navigate = useNavigate();

  const handleBackHome = () => {
    navigate("/"); // 跳转到首页
  };
  return (
    <Result
      status="404"
      title="404"
      subTitle="Sorry, the page you visited does not exist."
      extra={
        <Button type="primary" onClick={handleBackHome}>
          Back Home
        </Button>
      }
    />
  );
};
export default Page404;
