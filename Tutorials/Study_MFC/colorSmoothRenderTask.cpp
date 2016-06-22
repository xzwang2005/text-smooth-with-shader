#include "stdafx.h"
#include "colorSmoothRenderTask.h"
#include "Entity3D.h"
#include "Scene.h"
#include "Texture2dConfigDX11.h"
#include "Log.h"
#include "ActorGenerator.h"
#include "IParameterManager.h"
#include "DepthStencilViewConfigDX11.h"
#include "ShaderResourceViewConfigDX11.h"

using namespace Glyph3;

ColorSmoothRenderTask::ColorSmoothRenderTask(RendererDX11 & Renderer, ResourcePtr RenderTarget, FLOAT magLevel)
{
	m_BackBuffer = RenderTarget;
	D3D11_TEXTURE2D_DESC desc = m_BackBuffer->m_pTexture2dConfig->GetTextureDesc();

	ResolutionX = desc.Width;
	ResolutionY = desc.Height;

	m_magnifyLevel = magLevel;
	UpdateDiscreteSurfDimension();

	// Create render targets
	Texture2dConfigDX11 RTConfig;
	RTConfig.SetColorBuffer(m_discreteSurfWidth, m_discreteSurfHeight);
	RTConfig.SetBindFlags(D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE);
	RTConfig.SetFormat(DXGI_FORMAT_R32G32B32A32_FLOAT);
	m_discretePathTargets.push_back( Renderer.CreateTexture2D(&RTConfig, NULL) );

	//RTConfig.SetFormat(DXGI_FORMAT_R16G16B16A16_FLOAT);
	m_euclideanPathTarget.push_back( Renderer.CreateTexture2D(&RTConfig, NULL));

	RTConfig.SetFormat(DXGI_FORMAT_R16G16B16A16_FLOAT);
	m_discretePathTargets.push_back( Renderer.CreateTexture2D(&RTConfig, NULL) );

	m_fullConnectedDiscretePathTargets.push_back(Renderer.CreateTexture2D(&RTConfig, NULL));

	// target for magnify pass
	Texture2dConfigDX11 magRTConfig;
	magRTConfig.SetColorBuffer(ResolutionX, ResolutionY);
	magRTConfig.SetFormat(DXGI_FORMAT_R32G32B32A32_FLOAT);
	magRTConfig.SetBindFlags(D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE);
	m_magnifyTargets.push_back(Renderer.CreateTexture2D(&magRTConfig, NULL));
	m_magnifyTargets.push_back(Renderer.CreateTexture2D(&magRTConfig, NULL));

	Texture2dConfigDX11 DepthConfig;
	DepthConfig.SetDepthBuffer(m_discreteSurfWidth, m_discreteSurfHeight);
	m_discretePathSurfaceDepthTarget = Renderer.CreateTexture2D(&DepthConfig, NULL);
	m_euclideanPathDepthTarget = Renderer.CreateTexture2D(&DepthConfig, NULL);
	m_fullConnectedDiscretePathDepthTarget = Renderer.CreateTexture2D(&DepthConfig, NULL);

	DepthConfig.SetDepthBuffer(ResolutionX, ResolutionY);
	m_magnifyDepthTarget = Renderer.CreateTexture2D(&DepthConfig, NULL);
	m_DepthTarget = Renderer.CreateTexture2D(&DepthConfig, NULL);

	m_pViewportSurfParam = Renderer.m_pParamMgr->GetShaderResourceParameterRef(std::wstring(_T("ViewportSurface")));
	m_pDiscreteSurfParam = Renderer.m_pParamMgr->GetShaderResourceParameterRef(std::wstring(_T("DiscretePathSurface")));
	m_pEuclideanSurfParam = Renderer.m_pParamMgr->GetShaderResourceParameterRef(std::wstring(_T("EucldeanSurface")));
	m_pFullConnectedDiscreteSurfParam = Renderer.m_pParamMgr->GetShaderResourceParameterRef(std::wstring(_T("FullConnectedDiscretePathSurface")));

	m_pMagnifySurfParam = Renderer.m_pParamMgr->GetShaderResourceParameterRef(std::wstring(_T("MagnifyedSurface")));
	m_pMagnifyDefectSurfParam = Renderer.m_pParamMgr->GetShaderResourceParameterRef(std::wstring(_T("DefectSurface")));

	D3D11_VIEWPORT viewport;
	viewport.Width = static_cast<float>(ResolutionX);
	viewport.Height = static_cast<float>(ResolutionY);
	viewport.MinDepth = 0.0f;
	viewport.MaxDepth = 1.0f;
	viewport.TopLeftX = 0;
	viewport.TopLeftY = 0;

	m_iViewport = Renderer.CreateViewPort(viewport);

	m_pDiscretePathView = new DiscretePathRenderer(Renderer);
	m_pDiscretePathView->SetBackColor(Glyph3::Vector4f(0.6f, 0.6f, 0.9f, 1.0f));

	m_pFullConnectedPointView = new FullConnectedInterPixelRenderer(Renderer);
	m_pFullConnectedPointView->SetBackColor(Glyph3::Vector4f(0.6f, 0.6f, 0.9f, 1.0f));

	m_pEuclideanPathView = new EuclideanPathRenderer(Renderer);
	m_pEuclideanPathView->SetBackColor(Glyph3::Vector4f(0.6f, 0.6f, 0.9f, 1.0f));

	m_pMagnifyView = new MagnifyRenderer(Renderer);
	m_pMagnifyView->SetBackColor(Glyph3::Vector4f(0.6f, 0.6f, 0.9f, 1.0f));
}

ColorSmoothRenderTask::~ColorSmoothRenderTask()
{
	SAFE_DELETE(m_pDiscretePathView);
	SAFE_DELETE(m_pFullConnectedPointView);
	SAFE_DELETE(m_pEuclideanPathView);
	SAFE_DELETE(m_pMagnifyView);
}

void ColorSmoothRenderTask::Update(float fTime)
{}

void ColorSmoothRenderTask::QueuePreTasks(RendererDX11* pRenderer)
{
	if (m_pEntity != NULL)
	{
		Matrix4f view = m_pEntity->Transform.GetView();
		SetViewMatrix(view);
	}

	// Queue this view into the renderer for processing.
	pRenderer->QueueTask(this);

	if (m_pScene)
	{
		// Run through the graph and pre-render the entities
		m_pScene->GetRoot()->PreRender(pRenderer, VT_FINALPASS);
	}

	SetupViews();

	m_pMagnifyView->QueuePreTasks(pRenderer);
	m_pEuclideanPathView->QueuePreTasks(pRenderer);
	m_pFullConnectedPointView->QueuePreTasks(pRenderer);
	m_pDiscretePathView->QueuePreTasks(pRenderer);
}

void ColorSmoothRenderTask::ExecuteTask(PipelineManagerDX11* pPipelineManager, IParameterManager* pParamManager)
{
	if (m_pScene)
	{
		// Set the render target for the final pass, and clear it
		pPipelineManager->ClearRenderTargets();
		pPipelineManager->OutputMergerStage.DesiredState.RenderTargetViews.SetState(0, m_BackBuffer->m_iResourceRTV);
		pPipelineManager->OutputMergerStage.DesiredState.DepthTargetViews.SetState(m_DepthTarget->m_iResourceDSV);
		pPipelineManager->ApplyRenderTargets();
		pPipelineManager->ClearBuffers(Vector4f(0.0f, 0.0f, 0.0f, 0.0f));

		// Configure the desired viewports in this pipeline
		ConfigureViewports(pPipelineManager);

		// Set this view's render parameters
		SetRenderParams(pParamManager);

		// Run through the graph and render each of the entities
		m_pScene->GetRoot()->Render(pPipelineManager, pParamManager, VT_FINALPASS);
	}
}

void ColorSmoothRenderTask::SetupViews()
{
	SetViewPort(m_iViewport);
	m_pDiscretePathView->SetTargets(m_discretePathTargets, m_discretePathSurfaceDepthTarget, m_iViewport);

	m_pFullConnectedPointView->SetTargets(m_fullConnectedDiscretePathTargets, m_fullConnectedDiscretePathDepthTarget, m_discretePathTargets[1], m_discretePathTargets[0], m_iViewport);

	m_pEuclideanPathView->SetTargets(m_euclideanPathTarget, m_euclideanPathDepthTarget, m_fullConnectedDiscretePathTargets[0], m_iViewport);

	m_pMagnifyView->SetTargets(m_magnifyTargets, m_magnifyDepthTarget, m_euclideanPathTarget[0], m_discretePathTargets[0], m_fullConnectedDiscretePathTargets[0], m_magnifyLevel, m_iViewport);
}

void ColorSmoothRenderTask::UpdateDiscreteSurfDimension()
{
	m_discreteSurfWidth = ResolutionX / m_magnifyLevel + 2;
	m_discreteSurfHeight = ResolutionY / m_magnifyLevel + 2;
}

void ColorSmoothRenderTask::Resize(UINT width, UINT height)
{
	ResolutionX = width;
	ResolutionY = height;

	RendererDX11* pRenderer = RendererDX11::Get();
	// NOTE: need to manually resize the depth target of this renderer
	pRenderer->ResizeTexture(m_DepthTarget, width, height);
	pRenderer->ResizeViewport(m_iViewport, width, height);

	UpdateDiscreteSurfDimension();
	// resize the discrete surface
	for (size_t i = 0; i < m_discretePathTargets.size(); ++i)
		pRenderer->ResizeTexture(m_discretePathTargets[i], m_discreteSurfWidth, m_discreteSurfHeight);
	pRenderer->ResizeTexture(m_discretePathSurfaceDepthTarget, m_discreteSurfWidth, m_discreteSurfHeight);
	m_pDiscretePathView->Resize(m_discreteSurfWidth, m_discreteSurfHeight);

	for (size_t i = 0; i < m_fullConnectedDiscretePathTargets.size(); ++i)
		pRenderer->ResizeTexture(m_fullConnectedDiscretePathTargets[i], m_discreteSurfWidth, m_discreteSurfHeight);
	pRenderer->ResizeTexture(m_fullConnectedDiscretePathDepthTarget, m_discreteSurfWidth, m_discreteSurfHeight);

	pRenderer->ResizeTexture(m_euclideanPathTarget[0], m_discreteSurfWidth, m_discreteSurfHeight);
	pRenderer->ResizeTexture(m_euclideanPathDepthTarget, m_discreteSurfWidth, m_discreteSurfHeight);

	for (size_t i = 0; i < m_magnifyTargets.size(); ++i) {
		pRenderer->ResizeTexture(m_magnifyTargets[i], width, height);
	}
	pRenderer->ResizeTexture(m_magnifyDepthTarget, width, height);

	//m_pEuclideanPathView->Resize(m_discreteSurfWidth, m_discreteSurfHeight);
}

void ColorSmoothRenderTask::SetMagnifyLevel(FLOAT lvl)
{
	//if (lvl == m_magnifyLevel) return;
	m_magnifyLevel = lvl;
	UpdateDiscreteSurfDimension();

	// adjust size
	for (size_t i = 0; i < m_discretePathTargets.size(); ++i)
		RendererDX11::Get()->ResizeTexture(m_discretePathTargets[i], m_discreteSurfWidth, m_discreteSurfHeight);
	RendererDX11::Get()->ResizeTexture(m_discretePathSurfaceDepthTarget, m_discreteSurfWidth, m_discreteSurfHeight);

	for (size_t i = 0; i < m_fullConnectedDiscretePathTargets.size(); ++i)
		RendererDX11::Get()->ResizeTexture(m_fullConnectedDiscretePathTargets[i], m_discreteSurfWidth, m_discreteSurfHeight);
	RendererDX11::Get()->ResizeTexture(m_fullConnectedDiscretePathDepthTarget, m_discreteSurfWidth, m_discreteSurfHeight);

	RendererDX11::Get()->ResizeTexture(m_euclideanPathTarget[0], m_discreteSurfWidth, m_discreteSurfHeight);
	RendererDX11::Get()->ResizeTexture(m_euclideanPathDepthTarget, m_discreteSurfWidth, m_discreteSurfHeight);
}

void ColorSmoothRenderTask::SetEntity(Glyph3::Entity3D* pEntity)
{
	m_pEntity = pEntity;
	m_pDiscretePathView->SetEntity(pEntity);
	m_pFullConnectedPointView->SetEntity(pEntity);
	m_pEuclideanPathView->SetEntity(pEntity);
	m_pMagnifyView->SetEntity(pEntity);
}

void ColorSmoothRenderTask::SetScene(Scene* pScene)
{
	m_pScene = pScene;
	m_pDiscretePathView->SetScene(pScene);
	m_pFullConnectedPointView->SetScene(pScene);
	m_pEuclideanPathView->SetScene(pScene);
	m_pMagnifyView->SetScene(pScene);
}

void ColorSmoothRenderTask::SetRenderParams(IParameterManager* pParamManager)
{
	pParamManager->SetViewMatrixParameter(&ViewMatrix);
	pParamManager->SetProjMatrixParameter(&ProjMatrix);
	
	pParamManager->SetShaderResourceParameter(m_pViewportSurfParam, m_discretePathTargets[0]);
	pParamManager->SetShaderResourceParameter(m_pDiscreteSurfParam, m_discretePathTargets[1]);
	pParamManager->SetShaderResourceParameter(m_pFullConnectedDiscreteSurfParam, m_fullConnectedDiscretePathTargets[0]);
	pParamManager->SetShaderResourceParameter(m_pEuclideanSurfParam, m_euclideanPathTarget[0]);

	pParamManager->SetShaderResourceParameter(m_pMagnifySurfParam, m_magnifyTargets[0]);
	pParamManager->SetShaderResourceParameter(m_pMagnifyDefectSurfParam, m_magnifyTargets[1]);
}

void ColorSmoothRenderTask::SetUsageParams(IParameterManager* pParamManager)
{}

std::wstring ColorSmoothRenderTask::GetName()
{
	return(L"ColorSmoothRenderer");
}
