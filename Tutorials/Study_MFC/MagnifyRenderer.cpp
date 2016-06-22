#include "stdafx.h"
#include "MagnifyRenderer.h"
#include "Entity3D.h"
#include "Scene.h"
#include "Texture2dConfigDX11.h"
#include "Log.h"
#include "IParameterManager.h"
#include "PipelineManagerDX11.h"
#include "Texture2dDX11.h"
#include <tchar.h>

using namespace Glyph3;
class Glyph3::Entity3D;

MagnifyRenderer::MagnifyRenderer(RendererDX11& Renderer)
	: m_Renderer(Renderer)
{
	ViewMatrix.MakeIdentity();
	ProjMatrix.MakeIdentity();

	m_pEuclideanSurfParam = Renderer.m_pParamMgr->GetShaderResourceParameterRef(std::wstring(_T("EucldeanSurface")));
	m_pViewportSurfParam = Renderer.m_pParamMgr->GetShaderResourceParameterRef(std::wstring(_T("ViewportSurface")));
	m_pFullConnectedSurfParam = Renderer.m_pParamMgr->GetShaderResourceParameterRef(std::wstring(_T("FullConnectedDiscretePathSurface")));
	m_pMagnifyLevelParameter = Renderer.m_pParamMgr->GetVectorParameterRef(std::wstring(L"MagnifyLevel"));
}


MagnifyRenderer::~MagnifyRenderer()
{
}


void MagnifyRenderer::SetTargets(
	std::vector<ResourcePtr>& renderTargets,
	ResourcePtr DepthTarget,
	ResourcePtr euclideanSurf,
	ResourcePtr	viewportSurf,
	ResourcePtr fCodeSurf,
	int	magLevel,
	int Viewport)
{
	m_renderTargets = renderTargets;
	SetViewPort(Viewport);
	m_DepthTarget = DepthTarget;
	m_EuclideanSurf = euclideanSurf;
	m_viewPortSurf = viewportSurf;
	m_magnifyLevel = magLevel;
	m_fullConnectedSurf = fCodeSurf;
	m_magParam = Glyph3::Vector2f((float)m_magnifyLevel, (float)m_magnifyLevel);
	m_pMagnifyLevelParameter->InitializeParameterData(&m_magParam);
}

void MagnifyRenderer::Update(float fTime)
{
}

void MagnifyRenderer::QueuePreTasks(RendererDX11* pRenderer)
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
		m_pScene->PreRender(pRenderer, VT_LIGHTS);
	}
}

void MagnifyRenderer::ExecuteTask(PipelineManagerDX11* pPipelineManager, IParameterManager* pParamManager)
{
	if (m_pScene)
	{
		// Set the parameters for rendering this view
		pPipelineManager->ClearRenderTargets();
		for (unsigned int i = 0; i < m_renderTargets.size(); ++i)
			pPipelineManager->OutputMergerStage.DesiredState.RenderTargetViews.SetState(i, m_renderTargets[i]->m_iResourceRTV);
		pPipelineManager->OutputMergerStage.DesiredState.DepthTargetViews.SetState(m_DepthTarget->m_iResourceDSV);
		pPipelineManager->ApplyRenderTargets();

		pPipelineManager->ClearBuffers(m_vColor, 1.0f);

		// Configure the desired viewports in this pipeline
		ConfigureViewports(pPipelineManager);

		// Set this view's render parameters
		SetRenderParams(pParamManager);

		// Run through the graph and render each of the entities
		m_pScene->GetRoot()->Render(pPipelineManager, pParamManager, VT_LIGHTS);
	}
}

void MagnifyRenderer::Resize(UINT width, UINT height)
{
}


std::wstring MagnifyRenderer::GetName()
{
	return(L"MagnifyRenderer");
}

void MagnifyRenderer::SetRenderParams(IParameterManager* pParamManager)
{
	pParamManager->SetViewMatrixParameter(&ViewMatrix);
	pParamManager->SetProjMatrixParameter(&ProjMatrix);
	pParamManager->SetShaderResourceParameter(m_pEuclideanSurfParam, m_EuclideanSurf);
	pParamManager->SetShaderResourceParameter(m_pViewportSurfParam, m_viewPortSurf);
	pParamManager->SetShaderResourceParameter(m_pFullConnectedSurfParam, m_fullConnectedSurf);
}